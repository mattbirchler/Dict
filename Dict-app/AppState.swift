import Foundation

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
    var lastError: String?
    var foundationModelsAvailable: Bool { pipeline.aiCleanupService.isAvailable }
    var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") }
        set { UserDefaults.standard.set(newValue, forKey: "hasCompletedOnboarding") }
    }

    func startRecording() {
        guard isEnabled, !isRecording, !isProcessing else { return }
        isRecording = true
        lastError = nil
        pipeline.startRecording()
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        isProcessing = true

        Task {
            let result = await pipeline.stopRecordingAndProcess()
            isProcessing = false
            onProcessingComplete?()
            if result == nil {
                lastError = "Transcription failed. Please try again."
            }
        }
    }
}
