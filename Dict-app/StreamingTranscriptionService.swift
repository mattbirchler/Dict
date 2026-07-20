import Foundation
import CoreAudio
import WhisperKit

/// Accumulates microphone buffers until a natural pause completes a speech
/// segment. The completed segment can then be transcribed while recording
/// continues, leaving only the final segment to process after key-up.
struct SpeechSegmentAccumulator {
    let silenceThreshold: Float
    let silenceSamplesToSplit: Int
    let minimumSegmentSamples: Int
    let minimumVoicedSamples: Int

    private(set) var latestRMS: Float = 0
    private var samples: [Float] = []
    private var trailingSilenceSamples = 0
    private var voicedSamples = 0
    private var hasDetectedVoice = false

    init(
        sampleRate: Int = WhisperKit.sampleRate,
        silenceThreshold: Float = VoiceGate.absoluteFloor,
        silenceDuration: TimeInterval = 1.0,
        minimumSegmentDuration: TimeInterval = 1.5,
        minimumVoicedDuration: TimeInterval = 0.2
    ) {
        self.silenceThreshold = silenceThreshold
        self.silenceSamplesToSplit = Int(Double(sampleRate) * silenceDuration)
        self.minimumSegmentSamples = Int(Double(sampleRate) * minimumSegmentDuration)
        self.minimumVoicedSamples = Int(Double(sampleRate) * minimumVoicedDuration)
    }

    mutating func append(_ buffer: [Float]) -> [Float]? {
        guard !buffer.isEmpty else { return nil }
        samples.append(contentsOf: buffer)
        latestRMS = VoiceGate.frameEnergies(samples: buffer, frameSamples: buffer.count).first ?? 0

        if latestRMS > silenceThreshold {
            hasDetectedVoice = true
            voicedSamples += buffer.count
            trailingSilenceSamples = 0
        } else if hasDetectedVoice {
            trailingSilenceSamples += buffer.count
        }

        guard hasDetectedVoice,
              voicedSamples >= minimumVoicedSamples,
              samples.count >= minimumSegmentSamples,
              trailingSilenceSamples >= silenceSamplesToSplit else {
            return nil
        }
        return takeBufferedSamples()
    }

    mutating func finish() -> [Float]? {
        guard hasDetectedVoice else {
            reset()
            return nil
        }
        return takeBufferedSamples()
    }

    mutating func reset() {
        samples = []
        latestRMS = 0
        trailingSilenceSamples = 0
        voicedSamples = 0
        hasDetectedVoice = false
    }

    private mutating func takeBufferedSamples() -> [Float] {
        let completed = samples
        reset()
        return completed
    }
}

/// Records through WhisperKit and decodes completed speech segments
/// sequentially in the background. The HUD receives energy updates from the
/// same ordered audio stream used for segmentation.
@Observable
@MainActor
final class StreamingTranscriptionService {
    private var pipe: WhisperKit?
    private var isLoading = false
    /// Bumped by cancel()/stop() so an in-flight start() (suspended in
    /// ensureLoaded) knows the session it was starting is already over.
    private var session = 0
    private var activeSession: Int?
    private var recordingStartedAt: TimeInterval?

    private var audioBufferContinuation: AsyncStream<[Float]>.Continuation?
    private var audioConsumerTask: Task<Void, Never>?
    private var segmenter = SpeechSegmentAccumulator()

    private struct QueuedSegment {
        let index: Int
        let session: Int
        let samples: [Float]
    }
    private var queuedSegments: [QueuedSegment] = []
    private var completedSegments: [Int: String] = [:]
    private var segmentProcessingTask: Task<Void, Never>?
    private var nextSegmentIndex = 0
    private var segmentsCompletedDuringRecording = 0

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

        // A cancelled Core ML call may take a moment to yield. Never let it
        // overlap a new recording's use of the shared WhisperKit pipeline.
        if let previousTask = segmentProcessingTask {
            previousTask.cancel()
            await previousTask.value
            segmentProcessingTask = nil
        }
        guard session == startedSession, !isRecording else { return }

        audioEnergy = []
        activeSession = startedSession
        segmenter.reset()
        queuedSegments = []
        completedSegments = [:]
        nextSegmentIndex = 0
        segmentsCompletedDuringRecording = 0

        let (audioStream, continuation) = AsyncStream<[Float]>.makeStream(
            bufferingPolicy: .unbounded
        )
        audioBufferContinuation = continuation
        audioConsumerTask = Task { @MainActor [weak self] in
            for await buffer in audioStream {
                guard let self, self.activeSession == startedSession else { break }
                self.consumeAudioBuffer(buffer, session: startedSession)
            }
        }

        // The callback runs on WhisperKit's audio thread. Yielding into the
        // AsyncStream is thread-safe and keeps segmentation work off that
        // realtime thread while preserving buffer order.
        let concreteAudioProcessor = pipe.audioProcessor as? AudioProcessor
        let audioCallback: ([Float]) -> Void = { buffer in
            continuation.yield(buffer)
            // Incremental processing owns the audio now, so do not also retain
            // an ever-growing full-recording copy inside WhisperKit.
            pipe.audioProcessor.purgeAudioSamples(keepingLast: 0)
        }
        do {
            // WhisperKit starts its audio engine before assigning the callback
            // passed to startRecordingLive. Preassign it so the first buffer
            // cannot arrive in that small window and be omitted.
            concreteAudioProcessor?.audioBufferCallback = audioCallback
            try pipe.audioProcessor.startRecordingLive(
                inputDeviceID: nil,
                callback: audioCallback
            )
        } catch {
            concreteAudioProcessor?.audioBufferCallback = nil
            continuation.finish()
            audioConsumerTask?.cancel()
            audioConsumerTask = nil
            audioBufferContinuation = nil
            activeSession = nil
            throw error
        }
        isRecording = true
        recordingStartedAt = ProcessInfo.processInfo.systemUptime

        print("[Transcription] Recording started")
    }

    /// Stops the engine and throws the recording away without transcribing —
    /// used when the hotkey was released before the accidental-tap threshold.
    func cancel() {
        session += 1
        let wasRecording = isRecording
        isRecording = false
        activeSession = nil
        audioBufferContinuation?.finish()
        audioBufferContinuation = nil
        audioConsumerTask?.cancel()
        audioConsumerTask = nil
        segmentProcessingTask?.cancel()
        queuedSegments = []
        completedSegments = [:]
        nextSegmentIndex = 0
        segmenter.reset()
        if wasRecording, let pipe {
            pipe.audioProcessor.stopRecording()
            (pipe.audioProcessor as? AudioProcessor)?.audioBufferCallback = nil
            pipe.audioProcessor.purgeAudioSamples(keepingLast: 0)
        }
        audioEnergy = []
        recordingStartedAt = nil
        print("[Transcription] Recording cancelled - discarded")
    }

    func stop() async -> String {
        let stopStarted = ProcessInfo.processInfo.systemUptime
        session += 1
        guard isRecording, let pipe, let stoppingSession = activeSession else { return "" }
        isRecording = false

        pipe.audioProcessor.stopRecording()
        (pipe.audioProcessor as? AudioProcessor)?.audioBufferCallback = nil
        audioBufferContinuation?.finish()
        audioBufferContinuation = nil
        await audioConsumerTask?.value
        audioConsumerTask = nil

        if let finalSegment = segmenter.finish() {
            enqueueSegment(finalSegment, session: stoppingSession)
        }
        pipe.audioProcessor.purgeAudioSamples(keepingLast: 0)
        audioEnergy = []

        // The active worker drains every queued segment in order, including
        // the final tail. Most earlier segments have already completed while
        // the user was still speaking.
        startSegmentWorkerIfNeeded()
        await segmentProcessingTask?.value

        guard activeSession == stoppingSession else { return "" }
        let text = (0..<nextSegmentIndex)
            .compactMap { completedSegments[$0] }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let recordingSeconds = recordingStartedAt.map {
            stopStarted - $0
        } ?? 0
        print(String(
            format: "[Timing] whisper recording=%.3fs segments=%d completedDuringRecording=%d postRelease=%.3fs",
            recordingSeconds,
            nextSegmentIndex,
            segmentsCompletedDuringRecording,
            ProcessInfo.processInfo.systemUptime - stopStarted
        ))
        print("[Transcription] Result: \"\(text)\"")

        activeSession = nil
        recordingStartedAt = nil
        queuedSegments = []
        completedSegments = [:]
        nextSegmentIndex = 0
        segmentsCompletedDuringRecording = 0
        return text
    }

    // MARK: - Incremental segment processing

    private func consumeAudioBuffer(_ buffer: [Float], session: Int) {
        guard activeSession == session else { return }
        let completedSegment = segmenter.append(buffer)

        // RMS values around 0.005...0.010 are normal speech on the reference
        // microphone. Keep a short rolling window for the HUD.
        audioEnergy.append(min(max(segmenter.latestRMS / 0.02, 0), 1))
        if audioEnergy.count > 64 {
            audioEnergy.removeFirst(audioEnergy.count - 64)
        }

        if let completedSegment {
            enqueueSegment(completedSegment, session: session)
        }
    }

    private func enqueueSegment(_ samples: [Float], session: Int) {
        guard activeSession == session, !samples.isEmpty else { return }
        let index = nextSegmentIndex
        nextSegmentIndex += 1
        queuedSegments.append(QueuedSegment(index: index, session: session, samples: samples))
        print(String(
            format: "[Transcription] Queued segment %d (%.2fs audio)",
            index,
            Double(samples.count) / Double(WhisperKit.sampleRate)
        ))
        startSegmentWorkerIfNeeded()
    }

    private func startSegmentWorkerIfNeeded() {
        guard segmentProcessingTask == nil, !queuedSegments.isEmpty else { return }
        segmentProcessingTask = Task { @MainActor [weak self] in
            await self?.processQueuedSegments()
        }
    }

    private func processQueuedSegments() async {
        defer { segmentProcessingTask = nil }
        while !queuedSegments.isEmpty, !Task.isCancelled {
            let segment = queuedSegments.removeFirst()
            guard activeSession == segment.session else { continue }
            let text = await transcribeSegment(segment.samples, index: segment.index)
            guard activeSession == segment.session, !Task.isCancelled else { return }
            completedSegments[segment.index] = text
            if isRecording {
                segmentsCompletedDuringRecording += 1
            }
        }
    }

    private func transcribeSegment(_ samples: [Float], index: Int) async -> String {
        guard let pipe else { return "" }
        let segmentStarted = ProcessInfo.processInfo.systemUptime
        let gateStarted = segmentStarted
        guard let gated = Self.gateAndTrim(samples: samples) else {
            print(String(
                format: "[Timing] whisperSegment=%d audio=%.2fs gate=%.3fs decode=0.000s result=no-voice",
                index,
                Double(samples.count) / Double(WhisperKit.sampleRate),
                ProcessInfo.processInfo.systemUptime - gateStarted
            ))
            return ""
        }
        let gateSeconds = ProcessInfo.processInfo.systemUptime - gateStarted
        let decodeStarted = ProcessInfo.processInfo.systemUptime

        do {
            let options = DecodingOptions(
                language: "en",
                temperature: 0.0,
                skipSpecialTokens: true,
                wordTimestamps: false
            )
            let results = try await pipe.transcribe(
                audioArray: gated.samples,
                decodeOptions: options
            )
            let text = TranscriptFilter().filteredText(
                segments: results.flatMap { $0.segments },
                voiceActivity: gated.voiceActivity,
                frameDuration: gated.frameDuration
            )
            print(String(
                format: "[Timing] whisperSegment=%d audio=%.2fs gate=%.3fs decode=%.3fs total=%.3fs chars=%d",
                index,
                Double(samples.count) / Double(WhisperKit.sampleRate),
                gateSeconds,
                ProcessInfo.processInfo.systemUptime - decodeStarted,
                ProcessInfo.processInfo.systemUptime - segmentStarted,
                text.count
            ))
            return text
        } catch {
            print("[Transcription] Segment \(index) failed: \(error)")
            return ""
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
