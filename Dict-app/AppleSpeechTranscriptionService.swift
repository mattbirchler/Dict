import Foundation
import AVFoundation
import Speech
import os

/// On-device transcription using Apple's SpeechAnalyzer/SpeechTranscriber
/// (macOS 26). Owns its own AVAudioEngine tap; feeds converted buffers into a
/// SpeechAnalyzer streaming session and returns the finalized transcript on
/// stop. English-only (en-US) for now.
@MainActor
@Observable
final class AppleSpeechTranscriptionService: TranscriptionEngine {
    var audioEnergy: [Float] = []
    var audioSpectrum: [Float] = []
    private var spectrumGain = SpectrumGain()
    private(set) var isRecording: Bool = false
    private(set) var isReady: Bool = false
    private(set) var needsDownload: Bool = false
    @ObservationIgnored var onProgress: ((Double) -> Void)?
    @ObservationIgnored var inputDeviceID: AudioDeviceID?

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
    private let capture = AudioCapture()
    /// Token of the capture this recording started; see AudioCapture.stop.
    private var captureGeneration: Int?
    /// Bumped by cancel()/stop() so an in-flight start() knows the session
    /// it was starting is already over.
    private var session = 0

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
        await capture.warmUp()
    }

    // MARK: - Recording lifecycle

    func start() async throws {
        guard !isRecording else { return }
        guard isReady, let analyzerFormat else {
            throw AppleSpeechError.notPrepared
        }
        let startedSession = session
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
                Log.engine.error("results stream error: \(String(describing: error), privacy: .public)")
            }
        }

        // The tap callback runs on a realtime audio thread: capture
        // Sendable/local values, never touch main-actor state directly
        // (energy is published via a MainActor Task hop). Buffers are
        // converted from whatever format they arrive in (TapConverter).
        let tapConverter = TapConverter(targetFormat: analyzerFormat)
        var generation: Int?
        do {
            generation = try await capture.start(deviceID: inputDeviceID) { [weak self] buffer in
                let level = Self.rmsLevel(buffer)
                let spectrum = SpectrumAnalyzer.bandAmplitudes(buffer)
                Task { @MainActor [weak self] in self?.appendEnergy(level, spectrum: spectrum) }
                if let converted = tapConverter.convert(buffer) {
                    builder.yield(AnalyzerInput(buffer: converted))
                }
            }
            // The key was released while the mic was still opening (a
            // second or more on Bluetooth); nobody else will stop this.
            guard session == startedSession else {
                await capture.stop(generation: generation)
                rollBackStart()
                return
            }
            try await analyzer.start(inputSequence: inputSequence)
        } catch {
            // Roll back everything start() created so a failed attempt can't
            // leave the mic open or orphan the results task / analyzer.
            await capture.stop(generation: generation)
            rollBackStart()
            Log.engine.error("start failed, rolled back: \(String(describing: error), privacy: .public)")
            throw error
        }
        captureGeneration = generation
        isRecording = true
        Log.engine.info("Recording started")
    }

    private func rollBackStart() {
        teardownAudio()
        resultsTask?.cancel()
        resultsTask = nil
        analyzer = nil
        transcriber = nil
    }

    func cancel() {
        session += 1
        guard isRecording else { return }
        isRecording = false
        let generation = captureGeneration
        Task { await capture.stop(generation: generation) }
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
        Log.engine.info("Recording cancelled")
    }

    func stop() async throws -> String {
        session += 1
        guard isRecording else { return "" }
        isRecording = false
        await capture.stop(generation: captureGeneration)
        teardownAudio()

        var finalizeError: Error?
        do {
            try await analyzer?.finalizeAndFinishThroughEndOfInput()
        } catch {
            Log.engine.error("finalize error: \(String(describing: error), privacy: .public)")
            finalizeError = error
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
        // A finalize failure with nothing recognized is a failure, not silence.
        if text.isEmpty, let finalizeError { throw finalizeError }
        Log.engine.info("Result: \"\(text, privacy: .private)\"")
        return text
    }

    /// Resets the HUD-facing audio state and ends the analyzer's input
    /// once the capture is stopped.
    private func teardownAudio() {
        captureGeneration = nil
        audioSpectrum = []
        spectrumGain = SpectrumGain()
        inputBuilder?.finish()
        inputBuilder = nil
    }

    private func appendEnergy(_ level: Float, spectrum: [Float]) {
        audioSpectrum = spectrumGain.levels(amplitudes: spectrum)
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
