import Foundation
import CoreAudio
import WhisperKit

/// Records audio via WhisperKit's AudioProcessor and transcribes the full
/// buffered recording in one shot on stop. The HUD polls `audioEnergy` for
/// the waveform while recording is active.
@Observable
@MainActor
final class StreamingTranscriptionService {
    private var pipe: WhisperKit?
    private var energyTimer: Timer?
    private var isLoading = false
    /// Bumped by cancel()/stop() so an in-flight start() (suspended in
    /// ensureLoaded) knows the session it was starting is already over.
    private var session = 0
    private var segmenter = SpeechSegmenter()
    private var decodeQueue: ChunkDecodeQueue?
    /// How many samples of audioProcessor.audioSamples have been fed to the
    /// segmenter already.
    private var sampleCursor = 0
    /// Text decoded so far this session, used as decoder context for the
    /// next chunk.
    private var contextText = ""
    /// Whether the segmenter ever completed a chunk mid-recording this
    /// session (as opposed to only the final tail at stop()). A recording
    /// short enough to never split gains nothing from streaming, so stop()
    /// takes the one-shot fallback path for it instead of the chunk path.
    private var hadStreamedChunk = false

    // Published state the HUD binds to.
    var audioEnergy: [Float] = []
    var isRecording: Bool = false

    var isModelLoaded: Bool { pipe != nil }
    var onProgress: ((Double) -> Void)?

    // MARK: - Model loading

    func ensureLoaded() async throws {
        guard pipe == nil, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        print("[WhisperKit] Downloading model...")
        let modelURL = try await WhisperKit.download(
            variant: "distil-large-v3",
            progressCallback: { [weak self] progress in
                Task { @MainActor in
                    self?.onProgress?(progress.fractionCompleted)
                }
            }
        )
        print("[WhisperKit] Model downloaded to: \(modelURL.path)")

        let config = WhisperKitConfig(
            modelFolder: modelURL.path,
            load: true,
            download: false
        )
        print("[WhisperKit] Loading model...")
        pipe = try await WhisperKit(config)
        print("[WhisperKit] Model loaded")
    }

    // MARK: - Recording lifecycle

    func start() async throws {
        let startedSession = session
        try await ensureLoaded()

        guard let pipe else {
            throw StreamingTranscriptionError.modelNotLoaded
        }
        // Cancelled or stopped while ensureLoaded was suspended — don't
        // start an engine nobody will stop.
        guard session == startedSession, !isRecording else { return }

        audioEnergy = []

        // Reset on start, not only on stop: state cleared only on the success
        // path leaks whenever the failure path runs.
        segmenter.reset()
        sampleCursor = 0
        contextText = ""
        hadStreamedChunk = false
        let pipeForDecode = pipe
        // Seed the new queue's serialization chain from the outgoing one
        // (if any) so a decode enqueued here can never run concurrently
        // with an in-flight decode orphaned by a fast cancel()-then-start()
        // (e.g. AppState.handleEngineChange switching engines mid-recording).
        let outgoingQueue = decodeQueue
        decodeQueue = ChunkDecodeQueue(after: outgoingQueue) { request in
            await Self.decodeChunk(pipe: pipeForDecode, request: request)
        }

        // startRecordingLive resets the internal audioSamples buffer and
        // begins accumulating samples. We don't need the buffer callback —
        // we poll relativeEnergy via a timer for the waveform.
        try pipe.audioProcessor.startRecordingLive(inputDeviceID: nil, callback: nil)
        isRecording = true

        let pipeRef = pipe
        energyTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isRecording else { return }
                self.audioEnergy = pipeRef.audioProcessor.relativeEnergy
                self.consumeNewAudio(from: pipeRef)
            }
        }

        print("[Transcription] Recording started")
    }

    /// Feeds newly arrived samples to the segmenter and enqueues any chunk
    /// the pause detector completes.
    private func consumeNewAudio(from pipe: WhisperKit) {
        let all = pipe.audioProcessor.audioSamples
        guard all.count > sampleCursor else { return }
        let fresh = Array(all[sampleCursor..<all.count])
        sampleCursor = all.count
        guard let chunk = segmenter.append(fresh), let queue = decodeQueue else { return }
        hadStreamedChunk = true
        let handle = queue.enqueue(ChunkDecodeQueue.Request(
            samples: chunk,
            promptText: contextText,
            threshold: segmenter.sessionThreshold
        ))
        // Extend the decoder context as soon as this chunk lands so the next
        // chunk is prompted with it. Snapshot the session counter so that if
        // this decode resolves after a NEW recording has already started
        // (and reset contextText), it doesn't append this stale session's
        // text into the new session's prompt context.
        //
        // This context carry-over is best-effort by design, not guaranteed:
        // the NEXT chunk is enqueued as soon as the segmenter finds its
        // boundary, whether or not THIS chunk's decode (awaited below) has
        // resolved yet. If it hasn't, chunk N+1 gets enqueued with whatever
        // contextText held before this append runs, so it's prompted with a
        // stale (or, for the first two chunks, empty) tail instead of this
        // chunk's actual text — and at stop() the final tail may miss the
        // most recent chunk's text entirely. Blocking chunk N+1's enqueue on
        // chunk N's decode would fix that but would also serialize chunk
        // boundaries behind decode latency, defeating the point of
        // streaming. It degrades gracefully instead: a missing/stale prompt
        // just means TranscriptAssembler.deduplicated finds no boundary
        // overlap to strip, so the seam is left un-deduplicated rather than
        // wrong.
        let startedSession = session
        Task { @MainActor [weak self] in
            guard let text = await handle.value, !text.isEmpty else { return }
            guard let self, self.session == startedSession else { return }
            self.contextText += (self.contextText.isEmpty ? "" : " ") + text
        }
        print("[Streaming] Chunk enqueued: \(chunk.count) samples")
    }

    /// Stops the engine and throws the recording away without transcribing —
    /// used when the hotkey was released before the accidental-tap threshold.
    func cancel() {
        session += 1
        guard isRecording, let pipe else { return }
        isRecording = false
        energyTimer?.invalidate()
        energyTimer = nil
        decodeQueue?.cancelAll()
        // Deliberately NOT nilled out here: an already-running Core ML
        // decode on this queue's chain can't be interrupted by cancelAll(),
        // so the next start() seeds its replacement queue from this one
        // (see ChunkDecodeQueue.init(after:decode:)) to keep decodes on the
        // shared WhisperKit pipeline serialized across the cancel boundary.
        segmenter.reset()
        sampleCursor = 0
        contextText = ""
        hadStreamedChunk = false
        pipe.audioProcessor.stopRecording()
        audioEnergy = []
        print("[Transcription] Recording cancelled — discarded")
    }

    func stop() async -> String {
        session += 1
        guard isRecording, let pipe else { return "" }
        isRecording = false

        energyTimer?.invalidate()
        energyTimer = nil

        // Grab the full audio buffer, then stop the engine.
        let samples = Array(pipe.audioProcessor.audioSamples)
        pipe.audioProcessor.stopRecording()
        audioEnergy = []

        // Consume everything captured since the last 0.05s timer tick —
        // otherwise those samples never reach the segmenter and the tail
        // chunk (and therefore the streamed result) clips the final words.
        consumeNewAudio(from: pipe)

        // Take the tail and let it jump ahead of nothing: at most one chunk
        // decode can still be in flight.
        let tail = segmenter.finish()
        let queue = decodeQueue

        var streamedChunks: [String] = []
        var streamingFailed = false
        if hadStreamedChunk {
            // This session actually split into multiple chunks, so
            // streaming bought something — run the real chunk path.
            if let tail, let queue {
                queue.enqueue(ChunkDecodeQueue.Request(
                    samples: tail,
                    promptText: contextText,
                    threshold: segmenter.sessionThreshold
                ))
            }
            if let queue {
                streamedChunks = await queue.drain()
                streamingFailed = streamingFailed || queue.hasFailed
            }
        } else {
            // The recording never produced a chunk boundary, so it's short
            // enough that streaming gained nothing. Take the exact one-shot
            // path below (with its VAD gate) instead of decoding the tail
            // through the chunk path — per the spec, a recording that never
            // split should be "naturally identical to today's behavior".
            // A prior session's decode may still be seeded into this
            // queue's chain (see cancel()) even though nothing was ever
            // enqueued on it here; wait for that tail so the one-shot
            // decode below never overlaps it on the shared WhisperKit
            // pipeline.
            if let queue { _ = await queue.chainTail().value }
            print("[Streaming] No chunk boundaries this session, using one-shot decode")
        }
        // Mirror cancel(): don't null out decodeQueue until this queue's
        // work is actually finished (the drain()/chainTail() awaits above
        // are suspension points). If a start() races in on this run loop
        // while we're suspended there — a fast restart, same as cancel()
        // guards against — it reads decodeQueue as `outgoingQueue` to seed
        // its replacement via ChunkDecodeQueue.init(after:), so decodes
        // stay serialized on the shared WhisperKit pipeline across the stop
        // boundary too. Nilling it out early would make that seed empty,
        // letting the new session's first decode run concurrently with a
        // decode this queue still has in flight.
        //
        // If that race happened, decodeQueue now points at the NEW
        // session's queue, not `queue` — leave it alone so stop() doesn't
        // clobber a recording that's already started.
        if decodeQueue === queue {
            decodeQueue = nil
        }
        segmenter.reset()
        sampleCursor = 0
        contextText = ""
        hadStreamedChunk = false

        if !streamingFailed, !streamedChunks.isEmpty {
            let assembled = TranscriptAssembler.assemble(streamedChunks)
            if !assembled.isEmpty {
                print("[Streaming] Result from \(streamedChunks.count) chunk(s): \"\(assembled)\"")
                return assembled
            }
        }
        if streamingFailed || !streamedChunks.isEmpty {
            print("[Streaming] Falling back to one-shot decode (failed=\(streamingFailed), chunks=\(streamedChunks.count))")
        }

        print("[Transcription] Recording stopped — \(samples.count) samples, transcribing...")

        guard !samples.isEmpty else {
            print("[Transcription] No samples captured")
            return ""
        }

        guard let gated = Self.gateAndTrim(samples: samples) else {
            print("[Transcription] No voice activity detected, skipping transcription")
            return ""
        }
        let trimmedSamples = gated.samples
        let trimmedVoiceActivity = gated.voiceActivity
        let frameDuration = gated.frameDuration
        print("[Transcription] Trimmed \(samples.count) samples to \(trimmedSamples.count)")

        let decodeStarted = ProcessInfo.processInfo.systemUptime
        do {
            let options = DecodingOptions(
                language: "en",
                temperature: 0.0,
                skipSpecialTokens: true,
                wordTimestamps: false
            )
            let results = try await pipe.transcribe(
                audioArray: trimmedSamples,
                decodeOptions: options
            )
            let segments = results.flatMap { $0.segments }
            let text = TranscriptFilter().filteredText(
                segments: segments,
                voiceActivity: trimmedVoiceActivity,
                frameDuration: frameDuration
            )
            print(String(
                format: "[Timing] oneshot decode=%.3fs audio=%.1fs chars=%d",
                ProcessInfo.processInfo.systemUptime - decodeStarted,
                Float(trimmedSamples.count) / Float(WhisperKit.sampleRate),
                text.count
            ))
            print("[Transcription] Result: \"\(text)\"")
            return text
        } catch {
            print("[Transcription] Failed: \(error)")
            return ""
        }
    }

    /// Decodes one chunk with the previous chunk's text as decoder context.
    /// Returns nil on failure so the queue can mark the session degraded.
    ///
    /// Internal (not private) so StreamingEquivalenceTests can call the real
    /// decode-and-context-carry path via `@testable import` instead of
    /// re-implementing it, keeping the streaming ship gate honest.
    nonisolated static func decodeChunk(
        pipe: WhisperKit,
        request: ChunkDecodeQueue.Request
    ) async -> String? {
        var options = DecodingOptions(
            language: "en",
            temperature: 0.0,
            skipSpecialTokens: true,
            wordTimestamps: false
        )
        if !request.promptText.isEmpty, let tokenizer = pipe.tokenizer {
            let snippet = String(request.promptText.suffix(200))
            options.promptTokens = Array(tokenizer.encode(text: snippet).suffix(100))
            options.usePrefillPrompt = true
        }
        do {
            let results = try await pipe.transcribe(
                audioArray: request.samples,
                decodeOptions: options
            )
            let frameDuration: Float = 0.1
            let frameSamples = Int(frameDuration * Float(WhisperKit.sampleRate))
            let energies = VoiceGate.frameEnergies(
                samples: request.samples,
                frameSamples: frameSamples
            )
            // Session-wide threshold, so TranscriptFilter sees a consistent
            // baseline instead of re-deriving one per chunk.
            let activity = VoiceGate.voiceActivity(
                energies: energies,
                threshold: request.threshold
            )
            return TranscriptFilter().filteredText(
                segments: results.flatMap { $0.segments },
                voiceActivity: activity,
                frameDuration: frameDuration
            )
        } catch {
            print("[Streaming] Chunk decode failed: \(error)")
            return nil
        }
    }

    // MARK: - Gate and trim

    /// VAD gate: if the recording contains no detectable voice, skip
    /// Whisper entirely — decoding pure silence is what produces
    /// "Thank you." hallucinations. Otherwise trim leading/trailing
    /// silence (keeping 0.3s leading and 1s trailing padding) so Whisper
    /// never decodes long silent stretches at the edges. The threshold
    /// adapts to the recording's own noise floor (see VoiceGate).
    ///
    /// Extracted from stop() so integration tests can run real audio
    /// through the exact production path.
    nonisolated static func gateAndTrim(
        samples: [Float]
    ) -> (samples: [Float], voiceActivity: [Bool], frameDuration: Float)? {
        let frameDuration: Float = 0.1
        let frameSamples = Int(frameDuration * Float(WhisperKit.sampleRate))
        let energies = VoiceGate.frameEnergies(samples: samples, frameSamples: frameSamples)
        let voiceActivity = VoiceGate.voiceActivity(energies: energies)
        let sortedEnergies = energies.sorted()
        if !sortedEnergies.isEmpty {
            print(String(
                format: "[Transcription] Energy floor=%.4f median=%.4f max=%.4f voiced=%d/%d",
                sortedEnergies.first ?? 0,
                sortedEnergies[sortedEnergies.count / 2],
                sortedEnergies.last ?? 0,
                voiceActivity.count(where: { $0 }),
                voiceActivity.count
            ))
        }
        guard let frameRange = VoiceGate.activeFrameRange(
            voiceActivity: voiceActivity,
            paddingFrames: 3,
            trailingPaddingFrames: 10,
            minVoicedFrames: 2
        ) else {
            return nil
        }
        let sampleStart = frameRange.lowerBound * frameSamples
        let sampleEnd = min(samples.count, frameRange.upperBound * frameSamples)
        return (
            Array(samples[sampleStart..<sampleEnd]),
            Array(voiceActivity[frameRange]),
            frameDuration
        )
    }

    // MARK: - Mic name (for HUD label)

    static var inputDeviceName: String {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0, nil,
            &size, &deviceID
        )
        guard status == noErr else { return "Unknown Microphone" }

        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var nameSize = UInt32(MemoryLayout<CFString>.size)
        let nameStatus = AudioObjectGetPropertyData(
            deviceID,
            &nameAddress,
            0, nil,
            &nameSize, &name
        )
        guard nameStatus == noErr else { return "Unknown Microphone" }
        return name as String
    }
}

extension StreamingTranscriptionService: TranscriptionEngine {
    var isReady: Bool { isModelLoaded }
    var needsDownload: Bool { true }
    func prepare() async throws { try await ensureLoaded() }
}

enum StreamingTranscriptionError: LocalizedError {
    case modelNotLoaded

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "WhisperKit model failed to load."
        }
    }
}
