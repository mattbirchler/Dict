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
        try await ensureLoaded()

        guard let pipe else {
            throw StreamingTranscriptionError.modelNotLoaded
        }
        guard !isRecording else { return }

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

    func stop() async -> String {
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

        do {
            let options = DecodingOptions(
                language: "en",
                temperature: 0.0,
                skipSpecialTokens: true,
                wordTimestamps: false
            )
            let results = try await pipe.transcribe(
                audioArray: samples,
                decodeOptions: options
            )
            let text = results
                .map { $0.text }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            print("[Transcription] Result: \"\(text)\"")
            return text
        } catch {
            print("[Transcription] Failed: \(error)")
            return ""
        }
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

enum StreamingTranscriptionError: LocalizedError {
    case modelNotLoaded

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "WhisperKit model failed to load."
        }
    }
}
