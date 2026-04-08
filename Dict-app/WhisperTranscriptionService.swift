import Foundation
import WhisperKit

final class WhisperTranscriptionService {
    private var pipe: WhisperKit?
    private var isLoading = false
    var isModelLoaded: Bool { pipe != nil }
    var onProgress: ((Double) -> Void)?

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

    func transcribe(audioURL: URL) async throws -> String {
        try await ensureLoaded()

        guard let pipe else {
            throw WhisperTranscriptionError.modelNotLoaded
        }

        let options = DecodingOptions(
            skipSpecialTokens: true,
            wordTimestamps: false
        )

        let results = try await pipe.transcribe(
            audioPath: audioURL.path,
            decodeOptions: options
        )

        // Delete temp audio file
        try? FileManager.default.removeItem(at: audioURL)

        let text = results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        return text
    }
}

enum WhisperTranscriptionError: LocalizedError {
    case modelNotLoaded

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "WhisperKit model failed to load."
        }
    }
}
