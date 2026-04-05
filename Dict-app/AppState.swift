import Foundation

enum TranscriptionEngine: String, CaseIterable {
    case apple = "apple"
    case whisper = "whisper"

    var displayName: String {
        switch self {
        case .apple: return "Apple Speech"
        case .whisper: return "WhisperKit"
        }
    }
}

@Observable
final class AppState {
    let permissionChecker = PermissionChecker()
    let pipeline = PipelineCoordinator()

    var isEnabled = true {
        didSet { onEnabledChanged?(isEnabled) }
    }
    var onEnabledChanged: ((Bool) -> Void)?
    var onProcessingComplete: (() -> Void)?
    var isRecording = false
    var isProcessing = false
    var isLoadingWhisper = false
    var whisperDownloadProgress: Double = 0
    var lastError: String?
    var foundationModelsAvailable: Bool { pipeline.aiCleanupService.isAvailable }
    var aiCleanupEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "aiCleanupEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "aiCleanupEnabled") }
    }
    var transcriptionEngine: TranscriptionEngine {
        get {
            let raw = UserDefaults.standard.string(forKey: "transcriptionEngine") ?? TranscriptionEngine.apple.rawValue
            return TranscriptionEngine(rawValue: raw) ?? .apple
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "transcriptionEngine")
            if newValue == .whisper {
                preloadWhisperModel()
            }
        }
    }
    var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") }
        set { UserDefaults.standard.set(newValue, forKey: "hasCompletedOnboarding") }
    }

    func preloadWhisperModel() {
        guard !isLoadingWhisper else { return }
        isLoadingWhisper = true
        whisperDownloadProgress = 0
        pipeline.whisperTranscriptionService.onProgress = { [weak self] progress in
            self?.whisperDownloadProgress = progress
        }
        Task {
            do {
                try await pipeline.whisperTranscriptionService.ensureLoaded()
            } catch {
                print("[AppState] WhisperKit model failed to load: \(error)")
                lastError = "WhisperKit model failed to download."
            }
            isLoadingWhisper = false
            pipeline.whisperTranscriptionService.onProgress = nil
        }
    }

    func startRecording() {
        guard isEnabled, !isRecording, !isProcessing, !isLoadingWhisper else { return }
        isRecording = true
        lastError = nil
        pipeline.startRecording()
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        isProcessing = true

        Task {
            let result = await pipeline.stopRecordingAndProcess(
                aiCleanupEnabled: aiCleanupEnabled,
                transcriptionEngine: transcriptionEngine
            )
            isProcessing = false
            onProcessingComplete?()
            if result == nil {
                lastError = "Transcription failed. Please try again."
            }
        }
    }
}
