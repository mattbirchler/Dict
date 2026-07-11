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
    var onHotkeySettingsChanged: (() -> Void)?
    var isRecording = false
    var isProcessing = false

    // Mirror of the active engine's readiness, so SwiftUI observes concrete
    // AppState state rather than a type-erased TranscriptionEngine existential.
    var isPreparingEngine = false
    var isEngineReady = false
    var engineNeedsDownload = false
    var engineDownloadProgress: Double = 0

    var lastError: String?
    var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") }
        set { UserDefaults.standard.set(newValue, forKey: "hasCompletedOnboarding") }
    }

    init(settings: SettingsStore) {
        self.settings = settings
        pipeline.isFormattingEnabled = settings.isFormattingEnabled
        pipeline.historyStore.limit = settings.historyLimit
        pipeline.engineChoice = settings.transcriptionEngine
        refreshEngineReadiness()
        settings.onChange = { [weak self] change in
            guard let self else { return }
            switch change {
            case .formatting:
                self.pipeline.isFormattingEnabled = self.settings.isFormattingEnabled
            case .historyLimit:
                self.pipeline.historyStore.limit = self.settings.historyLimit
            case .hotkey, .activationMode:
                self.onHotkeySettingsChanged?()
            case .transcriptionEngine:
                self.handleEngineChange()
            }
        }
    }

    /// Read readiness from the active engine without starting any work.
    func refreshEngineReadiness() {
        let engine = pipeline.activeEngine
        isEngineReady = engine.isReady
        engineNeedsDownload = engine.needsDownload && !engine.isReady
    }

    private func handleEngineChange() {
        pipeline.engineChoice = settings.transcriptionEngine
        engineDownloadProgress = 0
        refreshEngineReadiness()
        // Apple prepares cheaply (no big download) — do it automatically.
        // Whisper's 1 GB download stays explicit (user taps Download in the UI).
        if settings.transcriptionEngine == .apple && !isEngineReady {
            prepareEngine()
        }
    }

    /// Download/install + load the active engine, mirroring progress/readiness.
    func prepareEngine() {
        guard !isPreparingEngine else { return }
        let engine = pipeline.activeEngine
        if engine.isReady {
            refreshEngineReadiness()
            return
        }
        isPreparingEngine = true
        engineDownloadProgress = 0
        engineNeedsDownload = engine.needsDownload
        engine.onProgress = { [weak self] progress in
            self?.engineDownloadProgress = progress
        }
        Task {
            do {
                try await engine.prepare()
            } catch {
                print("[AppState] Engine failed to prepare: \(error)")
                lastError = "Speech engine failed to prepare."
            }
            isPreparingEngine = false
            refreshEngineReadiness()
            engine.onProgress = nil
        }
    }

    func startRecording() {
        guard isEnabled, !isRecording, !isProcessing, !isPreparingEngine else { return }
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
