import AVFoundation
import FluidAudio
import Foundation
import os

/// On-device transcription using NVIDIA's Parakeet TDT model via FluidAudio's
/// CoreML port. Records the whole utterance through an AVAudioEngine tap and
/// decodes it in one shot at stop(): Parakeet decodes far faster than
/// realtime on Apple Silicon, so no mid-recording chunking is needed and the
/// model always sees the full utterance when punctuating.
@Observable
@MainActor
final class ParakeetTranscriptionService: TranscriptionEngine {
    var audioEnergy: [Float] = []
    private(set) var isRecording = false
    @ObservationIgnored var onProgress: ((Double) -> Void)?

    private static let modelVersion = AsrModelVersion.v3
    private static let sampleRate = 16_000
    private let maxEnergySamples = 64
    /// People release the hotkey while still finishing their last word, so
    /// keep capturing this long after stop() before shutting the mic off.
    static let releaseTail: Duration = .milliseconds(250)
    /// Silence added to both ends of the recording before decoding. The
    /// recording starts and stops abruptly at the hotkey, and Parakeet drops
    /// or garbles words that sit right at a hard edge.
    static let edgePaddingSeconds = 0.2

    private var manager: AsrManager?
    private var isPreparing = false
    /// Bumped by cancel()/stop() so an in-flight start() (suspended in
    /// prepare) knows the session it was starting is already over.
    private var session = 0
    private let audioEngine = AVAudioEngine()
    /// Recorded 16 kHz mono samples, appended from the realtime tap thread.
    /// Lock-protected rather than hopped to the main actor so stop() can't
    /// lose buffers that were still in flight between actors.
    private let recordedSamples = OSAllocatedUnfairLock(initialState: [Float]())

    var isReady: Bool { manager != nil }

    /// True until the model files are on disk; unlike Whisper this is
    /// re-checked against the cache, so a completed download flips it false
    /// across relaunches.
    var needsDownload: Bool {
        !AsrModels.modelsExist(
            at: AsrModels.defaultCacheDirectory(for: Self.modelVersion),
            version: Self.modelVersion
        )
    }

    // MARK: - Model loading

    func prepare() async throws {
        guard manager == nil, !isPreparing else { return }
        isPreparing = true
        defer { isPreparing = false }

        print("[Parakeet] Downloading/loading model...")
        let models = try await AsrModels.downloadAndLoad(
            version: Self.modelVersion,
            progressHandler: { [weak self] progress in
                let fraction = progress.fractionCompleted
                Task { @MainActor in self?.onProgress?(fraction) }
            }
        )
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        self.manager = manager
        print("[Parakeet] Model loaded")
        warmUpAudio()
    }

    // MARK: - Recording lifecycle

    func start() async throws {
        let startedSession = session
        try await prepare()
        guard manager != nil else { throw ParakeetTranscriptionError.modelNotLoaded }
        // Cancelled or stopped while prepare was suspended — don't start an
        // engine nobody will stop.
        guard session == startedSession, !isRecording else { return }

        recordedSamples.withLock { $0 = [] }
        audioEnergy = []

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(Self.sampleRate),
            channels: 1,
            interleaved: false
        ) else {
            throw ParakeetTranscriptionError.audioFormatUnavailable
        }

        // The tap callback runs on a realtime audio thread: append samples
        // under the lock, publish energy via a MainActor hop.
        let tapFormat = audioEngine.inputNode.outputFormat(forBus: 0)
        let converter = AVAudioConverter(from: tapFormat, to: targetFormat)
        let samplesBox = recordedSamples
        audioEngine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { [weak self] buffer, _ in
            let level = Self.rmsLevel(buffer)
            Task { @MainActor [weak self] in self?.appendEnergy(level) }
            guard let converter,
                  let converted = Self.convert(buffer, using: converter, to: targetFormat),
                  let channel = converted.floatChannelData?[0] else { return }
            let frames = Int(converted.frameLength)
            guard frames > 0 else { return }
            samplesBox.withLock {
                $0.append(contentsOf: UnsafeBufferPointer(start: channel, count: frames))
            }
        }
        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            // Roll back so a failed attempt can't leak the tap (a second
            // installTap on the same bus crashes).
            teardownAudio()
            throw error
        }
        isRecording = true
        print("[Parakeet] Recording started")
    }

    /// Stops the engine and throws the recording away without transcribing —
    /// used when the hotkey was released before the accidental-tap threshold.
    func cancel() {
        session += 1
        guard isRecording else { return }
        isRecording = false
        teardownAudio()
        recordedSamples.withLock { $0 = [] }
        audioEnergy = []
        print("[Parakeet] Recording cancelled — discarded")
    }

    func stop() async -> String {
        session += 1
        guard isRecording, manager != nil else { return "" }
        // Keep capturing through the release tail. A cancel() during the
        // sleep tears down and empties the buffer, so this stop returns "".
        try? await Task.sleep(for: Self.releaseTail)
        isRecording = false
        teardownAudio()
        audioEnergy = []

        let samples = recordedSamples.withLock { samples in
            let taken = samples
            samples = []
            return taken
        }
        let minimumSamples = ASRConstants.minimumRequiredSamples(forSampleRate: Self.sampleRate)
        guard samples.count >= minimumSamples else {
            print("[Parakeet] Recording too short (\(samples.count) samples), skipping")
            return ""
        }

        print("[Parakeet] Recording stopped — \(samples.count) samples, transcribing...")
        return await transcribeRecording(samples)
    }

    /// Decodes one full recording with a fresh decoder state. Internal (not
    /// private) so the end-to-end test can drive the exact production decode
    /// path via `@testable import` instead of re-implementing it.
    func transcribeRecording(_ samples: [Float]) async -> String {
        guard let manager else { return "" }
        let decodeStarted = ProcessInfo.processInfo.systemUptime
        do {
            var decoderState = try TdtDecoderState(decoderLayers: await manager.decoderLayerCount)
            let padded = Self.padded(samples, seconds: Self.edgePaddingSeconds, sampleRate: Self.sampleRate)
            let result = try await manager.transcribe(padded, decoderState: &decoderState)
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            print(String(
                format: "[Timing] parakeet decode=%.3fs audio=%.1fs chars=%d",
                ProcessInfo.processInfo.systemUptime - decodeStarted,
                Float(samples.count) / Float(Self.sampleRate),
                text.count
            ))
            print("[Parakeet] Result: \"\(text)\"")
            return text
        } catch {
            print("[Parakeet] Transcription failed: \(error)")
            return ""
        }
    }

    private func teardownAudio() {
        audioEngine.inputNode.removeTap(onBus: 0)
        if audioEngine.isRunning { audioEngine.stop() }
        warmUpAudio()
    }

    /// Creates the input node and allocates the engine's resources ahead of
    /// the next key press, so start() only has to begin IO and the first
    /// syllable isn't lost to engine setup. Preparing doesn't start capture,
    /// so the mic-in-use indicator stays off.
    private func warmUpAudio() {
        _ = audioEngine.inputNode
        audioEngine.prepare()
    }

    private func appendEnergy(_ level: Float) {
        audioEnergy.append(Self.normalizedEnergy(rms: level))
        if audioEnergy.count > maxEnergySamples {
            audioEnergy.removeFirst(audioEnergy.count - maxEnergySamples)
        }
    }

    // MARK: - Pure helpers (testable)

    /// Maps an RMS level (~0...0.3 for speech) into the 0...1 range the HUD
    /// waveform expects, matching the Apple engine's scaling.
    nonisolated static func normalizedEnergy(rms: Float) -> Float {
        min(max(rms * 6, 0), 1)
    }

    /// The recording with `seconds` of silence on each end.
    nonisolated static func padded(_ samples: [Float], seconds: Double, sampleRate: Int) -> [Float] {
        let silence = [Float](repeating: 0, count: Int(seconds * Double(sampleRate)))
        return silence + samples + silence
    }

    /// RMS of the first channel of a PCM buffer.
    nonisolated static func rmsLevel(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<count { let s = channel[i]; sum += s * s }
        return (sum / Float(count)).squareRoot()
    }

    /// Sample-rate-aware conversion from the tap format to 16 kHz mono.
    nonisolated static func convert(_ buffer: AVAudioPCMBuffer,
                                    using converter: AVAudioConverter,
                                    to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var supplied = false
        var err: NSError?
        converter.convert(to: out, error: &err) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        return err == nil ? out : nil
    }
}

enum ParakeetTranscriptionError: LocalizedError {
    case modelNotLoaded
    case audioFormatUnavailable

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "The Parakeet model failed to load."
        case .audioFormatUnavailable:
            return "Couldn't create a compatible audio format for Parakeet."
        }
    }
}
