import Foundation
import AVFoundation
import Speech

/// On-device transcription using Apple's SpeechAnalyzer/SpeechTranscriber
/// (macOS 26). Owns its own AVAudioEngine tap; feeds converted buffers into a
/// SpeechAnalyzer streaming session and returns the finalized transcript on
/// stop. English-only (en-US) for now.
@MainActor
@Observable
final class AppleSpeechTranscriptionService: TranscriptionEngine {
    var audioEnergy: [Float] = []
    private(set) var isRecording: Bool = false
    private(set) var isReady: Bool = false
    private(set) var needsDownload: Bool = false
    @ObservationIgnored var onProgress: ((Double) -> Void)?

    private let locale = Locale(identifier: "en-US")
    private let maxEnergySamples = 64

    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var analyzerFormat: AVAudioFormat?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var finalizedText = AttributedString()
    /// The latest not-yet-final result, replaced on every update.
    private var volatileText = AttributedString()
    let supportsLiveTranscript = true

    /// SpeechAnalyzer reports volatile results continuously, so the preview
    /// costs nothing extra and needs no beginLivePreview().
    var liveTranscript: LiveTranscript {
        LiveTranscript(
            confirmed: Self.plainText(finalizedText).trimmingCharacters(in: .whitespacesAndNewlines),
            tentative: Self.plainText(volatileText).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
    private let audioEngine = AVAudioEngine()

    // MARK: - Prepare (asset install)

    /// A `SpeechTranscriber` may only ever be attached to one `SpeechAnalyzer`.
    /// Reusing one across sessions traps inside `SpeechAnalyzer.setWorkers`, so
    /// every analyzer gets a freshly built module. Construction is cheap — the
    /// expensive part is asset installation, which is system-wide and already
    /// done by `prepare()`.
    private func makeTranscriber() -> SpeechTranscriber {
        SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
    }

    func prepare() async throws {
        if isReady { return }
        // Only used here to resolve locale support, asset state and audio
        // format; the recording session builds its own in start().
        let transcriber = makeTranscriber()

        let supported = await SpeechTranscriber.supportedLocales.contains {
            $0.identifier(.bcp47) == locale.identifier(.bcp47)
        }
        guard supported else { throw AppleSpeechError.localeUnsupported }

        let installed = await SpeechTranscriber.installedLocales.contains {
            $0.identifier(.bcp47) == locale.identifier(.bcp47)
        }
        if !installed {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                needsDownload = true
                let observation = request.progress.observe(\.fractionCompleted, options: [.initial, .new]) { [weak self] progress, _ in
                    let fraction = progress.fractionCompleted
                    Task { @MainActor in self?.onProgress?(fraction) }
                }
                defer { observation.invalidate() }
                try await request.downloadAndInstall()
                needsDownload = false
            }
        }

        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw AppleSpeechError.audioFormatUnavailable
        }
        analyzerFormat = format
        isReady = true
    }

    // MARK: - Recording lifecycle

    func start() async throws {
        guard !isRecording else { return }
        guard isReady, let analyzerFormat else {
            throw AppleSpeechError.notPrepared
        }
        finalizedText = AttributedString()
        volatileText = AttributedString()
        audioEnergy = []

        // Fresh module per session — see makeTranscriber().
        let transcriber = makeTranscriber()
        self.transcriber = transcriber

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer

        let (inputSequence, builder) = AsyncStream<AnalyzerInput>.makeStream()
        self.inputBuilder = builder

        // Drain results on the main actor (this Task inherits main-actor
        // isolation); accumulate finalized text, keep the latest volatile
        // result for the live preview.
        resultsTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await result in transcriber.results {
                    if result.isFinal {
                        self.finalizedText += result.text
                        self.volatileText = AttributedString()
                    } else {
                        self.volatileText = result.text
                    }
                }
            } catch {
                print("[AppleSpeech] results stream error: \(error)")
            }
        }

        // Install the mic tap. The callback runs on a realtime audio thread:
        // capture Sendable/local values, never touch main-actor state directly
        // (energy is published via a MainActor Task hop).
        let tapFormat = audioEngine.inputNode.outputFormat(forBus: 0)
        let converter = AVAudioConverter(from: tapFormat, to: analyzerFormat)
        let format = analyzerFormat
        do {
            audioEngine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { [weak self] buffer, _ in
                let level = Self.rmsLevel(buffer)
                Task { @MainActor [weak self] in self?.appendEnergy(level) }
                if let converter, let converted = Self.convert(buffer, using: converter, to: format) {
                    builder.yield(AnalyzerInput(buffer: converted))
                }
            }
            audioEngine.prepare()
            try audioEngine.start()
            try await analyzer.start(inputSequence: inputSequence)
        } catch {
            // Roll back everything start() created so a failed attempt can't
            // leak the tap (a second installTap on the same bus crashes) or
            // orphan the results task / analyzer.
            teardownAudio()
            resultsTask?.cancel()
            resultsTask = nil
            self.analyzer = nil
            print("[AppleSpeech] start failed, rolled back: \(error)")
            throw error
        }
        isRecording = true
        print("[AppleSpeech] Recording started")
    }

    func cancel() {
        guard isRecording else { return }
        isRecording = false
        teardownAudio()
        resultsTask?.cancel()
        resultsTask = nil
        let analyzer = self.analyzer
        self.analyzer = nil
        self.transcriber = nil
        finalizedText = AttributedString()
        volatileText = AttributedString()
        audioEnergy = []
        Task { await analyzer?.cancelAndFinishNow() }
        print("[AppleSpeech] Recording cancelled")
    }

    func stop() async -> String {
        guard isRecording else { return "" }
        isRecording = false
        teardownAudio()

        do {
            try await analyzer?.finalizeAndFinishThroughEndOfInput()
        } catch {
            print("[AppleSpeech] finalize error: \(error)")
        }
        // Let the results task drain the remaining finalized results.
        await resultsTask?.value
        resultsTask = nil
        analyzer = nil
        transcriber = nil
        audioEnergy = []

        let text = Self.plainText(finalizedText).trimmingCharacters(in: .whitespacesAndNewlines)
        finalizedText = AttributedString()
        volatileText = AttributedString()
        print("[AppleSpeech] Result: \"\(text)\"")
        return text
    }

    private func teardownAudio() {
        audioEngine.inputNode.removeTap(onBus: 0)
        if audioEngine.isRunning { audioEngine.stop() }
        inputBuilder?.finish()
        inputBuilder = nil
    }

    private func appendEnergy(_ level: Float) {
        audioEnergy.append(Self.normalizedEnergy(rms: level))
        if audioEnergy.count > maxEnergySamples {
            audioEnergy.removeFirst(audioEnergy.count - maxEnergySamples)
        }
    }

    // MARK: - Pure helpers (testable)

    /// RMS of a raw sample array. 0 for empty/silence.
    nonisolated static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sumSquares = samples.reduce(Float(0)) { $0 + $1 * $1 }
        return (sumSquares / Float(samples.count)).squareRoot()
    }

    /// Maps an RMS level (~0...0.3 for speech) into the 0...1 range the HUD
    /// waveform expects. Gain is tuned so normal speech lifts the bars; loud
    /// input clamps at 1.
    nonisolated static func normalizedEnergy(rms: Float) -> Float {
        min(max(rms * 6, 0), 1)
    }

    nonisolated static func plainText(_ attributed: AttributedString) -> String {
        String(attributed.characters)
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

    /// Sample-rate-aware conversion from the tap format to the analyzer format.
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

enum AppleSpeechError: LocalizedError {
    case localeUnsupported
    case notPrepared
    case audioFormatUnavailable

    var errorDescription: String? {
        switch self {
        case .localeUnsupported: "This language isn't supported by Apple's on-device speech engine."
        case .notPrepared: "The Apple speech engine isn't ready yet."
        case .audioFormatUnavailable: "Couldn't find a compatible audio format for Apple's speech engine."
        }
    }
}
