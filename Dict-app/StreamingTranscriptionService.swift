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
            }
        }

        print("[Transcription] Recording started")
    }

    /// Stops the engine and throws the recording away without transcribing —
    /// used when the hotkey was released before the accidental-tap threshold.
    func cancel() {
        session += 1
        guard isRecording, let pipe else { return }
        isRecording = false
        energyTimer?.invalidate()
        energyTimer = nil
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
            print("[Transcription] Result: \"\(text)\"")
            return text
        } catch {
            print("[Transcription] Failed: \(error)")
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
