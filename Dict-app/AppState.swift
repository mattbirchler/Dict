import Foundation

@MainActor
@Observable
final class AppState {
    let settings: SettingsStore
    let permissionChecker = PermissionChecker()
    let pipeline = PipelineCoordinator()

    var isEnabled = true {
        didSet { onEnabledChanged?(isEnabled) }
    }
    var onEnabledChanged: ((Bool) -> Void)?
    var onProcessingComplete: (() -> Void)?
    /// Fired when the hotkey or activation mode setting changes so the
    /// AppDelegate can reconfigure the KeyMonitor.
    var onHotkeySettingsChanged: (() -> Void)?
    var isRecording = false
    var isProcessing = false
    var isLoadingWhisper = false
    var whisperDownloadProgress: Double = 0
    var lastError: String?
    var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") }
        set { UserDefaults.standard.set(newValue, forKey: "hasCompletedOnboarding") }
    }

    init(settings: SettingsStore) {
        self.settings = settings
        pipeline.isFormattingEnabled = settings.isFormattingEnabled
        pipeline.historyStore.limit = settings.historyLimit
        settings.onChange = { [weak self] change in
            guard let self else { return }
            switch change {
            case .formatting:
                self.pipeline.isFormattingEnabled = self.settings.isFormattingEnabled
            case .historyLimit:
                self.pipeline.historyStore.limit = self.settings.historyLimit
            case .hotkey, .activationMode:
                self.onHotkeySettingsChanged?()
            }
        }
    }

    func preloadWhisperModel() {
        guard !isLoadingWhisper else { return }
        isLoadingWhisper = true
        whisperDownloadProgress = 0
        pipeline.transcriptionService.onProgress = { [weak self] progress in
            self?.whisperDownloadProgress = progress
        }
        Task {
            do {
                try await pipeline.transcriptionService.ensureLoaded()
            } catch {
                print("[AppState] WhisperKit model failed to load: \(error)")
                lastError = "WhisperKit model failed to download."
            }
            isLoadingWhisper = false
            pipeline.transcriptionService.onProgress = nil
        }
    }

    func startRecording() {
        guard isEnabled, !isRecording, !isProcessing, !isLoadingWhisper else { return }
        isRecording = true
        lastError = nil
        pipeline.startRecording()
    }

    func cancelRecording() {
        guard isRecording else { return }
        isRecording = false
        pipeline.cancelRecording()
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
