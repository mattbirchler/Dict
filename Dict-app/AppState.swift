import Foundation
import os

@MainActor
@Observable
final class AppState {
    let settings: SettingsStore
    /// Fired when the HUD color scheme setting changes.
    var onHUDColorSchemeChanged: ((HUDColorScheme) -> Void)?
    let permissionChecker = PermissionChecker()
    let pipeline = PipelineCoordinator()

    var isEnabled = true {
        didSet { onEnabledChanged?(isEnabled) }
    }
    var onEnabledChanged: ((Bool) -> Void)?
    /// Called when a dictation ends, with how it ended.
    var onProcessingComplete: ((DictationResult) -> Void)?
    var onHotkeySettingsChanged: (() -> Void)?
    /// Fired by onboarding the moment Accessibility is granted, so the
    /// key monitor can go in without waiting for the slow poller.
    var onAccessibilityGranted: (() -> Void)?

    // Parakeet downloading in the background while Apple keeps working.
    var isDownloadingParakeet = false
    var parakeetDownloadProgress: Double = 0
    var isParakeetReady: Bool { pipeline.parakeetEngine.isReady }
    var isRecording = false
    var isProcessing = false
    private var processingTask: Task<Void, Never>?
    /// Bumped when processing is cancelled, so a transcription that finishes
    /// afterwards can tell its result is no longer wanted.
    private var processingSession = 0

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
        SoundPlayer.isEnabled = settings.playsSounds
        pipeline.appendTrailingSpace = settings.appendTrailingSpace
        pipeline.smartLeadingSpace = settings.smartLeadingSpace
        pipeline.wordReplacements = settings.wordReplacements
        pipeline.historyStore.limit = settings.historyLimit
        pipeline.engineChoice = settings.transcriptionEngine
        pipeline.inputDeviceChoice = settings.inputDevice
        pipeline.onStartFailed = { [weak self] in
            guard let self, self.isRecording else { return }
            self.isRecording = false
            self.onProcessingComplete?(.failed)
        }
        refreshEngineReadiness()
        settings.onChange = { [weak self] change in
            guard let self else { return }
            switch change {
            case .formatting:
                self.pipeline.isFormattingEnabled = self.settings.isFormattingEnabled
            case .appendTrailingSpace:
                self.pipeline.appendTrailingSpace = self.settings.appendTrailingSpace
            case .smartLeadingSpace:
                self.pipeline.smartLeadingSpace = self.settings.smartLeadingSpace
            case .wordReplacements:
                self.pipeline.wordReplacements = self.settings.wordReplacements
            case .historyLimit:
                self.pipeline.historyStore.limit = self.settings.historyLimit
            case .hotkey, .activationMode:
                self.onHotkeySettingsChanged?()
            case .transcriptionEngine:
                self.handleEngineChange()
            case .inputDevice:
                self.pipeline.inputDeviceChoice = self.settings.inputDevice
            case .hudColorScheme:
                self.onHUDColorSchemeChanged?(self.settings.hudColorScheme)
            case .sounds:
                SoundPlayer.isEnabled = self.settings.playsSounds
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
        // If the user switches engines mid-recording (the Settings picker is
        // reachable during hands-free recording), tear down the engine that's
        // actually recording before it becomes unreachable via `activeEngine`
        // — otherwise its mic session is orphaned and the transcript is lost.
        let previous = pipeline.activeEngine
        if previous.isRecording {
            previous.cancel()
            if isRecording || isProcessing {
                isRecording = false
                isProcessing = false
                onProcessingComplete?(.cancelled)   // dismiss the recording HUD
            }
        }

        pipeline.engineChoice = settings.transcriptionEngine
        engineDownloadProgress = 0
        refreshEngineReadiness()
        // Engines that can prepare cheaply (no big download pending) do so
        // automatically: Apple always, Parakeet once its model is on disk.
        // First-time model downloads stay explicit (user taps Download in
        // the UI).
        if canAutoPrepare && !isEngineReady {
            prepareEngine()
        }
    }

    /// True when preparing the selected engine involves no user-visible
    /// model download, so it can be kicked off without an explicit tap.
    /// Internal so OnboardingWindow's auto-prepare hooks share the policy.
    var canAutoPrepare: Bool {
        switch settings.transcriptionEngine {
        case .apple: true
        case .parakeet: !engineNeedsDownload
        }
    }

    /// Download/install + load the active engine, mirroring progress/readiness.
    func prepareEngine() {
        guard !isPreparingEngine else { return }
        let engine = pipeline.activeEngine
        // A background Parakeet download already owns that engine's prepare.
        if isDownloadingParakeet, engine === pipeline.parakeetEngine { return }
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
                Log.app.error("Engine failed to prepare: \(String(describing: error), privacy: .public)")
                lastError = "Speech engine failed to prepare."
            }
            engine.onProgress = nil
            isPreparingEngine = false
            refreshEngineReadiness()
            // The user may have switched engines while this prepare was in
            // flight (the shared `isPreparingEngine` flag made concurrent
            // prepares no-op). If the now-active engine still needs preparing
            // and it's one that auto-prepares, kick it off now so the UI
            // can't get stuck "not ready, not preparing".
            if !isEngineReady && canAutoPrepare {
                prepareEngine()
            }
        }
    }

    /// Downloads and loads Parakeet without switching to it, so dictation
    /// keeps working on the current engine; once it is ready, Parakeet
    /// becomes the engine. A failure leaves the current engine selected.
    func downloadParakeet() {
        guard !isDownloadingParakeet, !isParakeetReady else { return }
        if settings.transcriptionEngine == .parakeet {
            // Already selected: the ordinary prepare path owns progress.
            prepareEngine()
            return
        }
        let engine = pipeline.parakeetEngine
        isDownloadingParakeet = true
        parakeetDownloadProgress = 0
        engine.onProgress = { [weak self] progress in
            self?.parakeetDownloadProgress = progress
        }
        Task {
            do {
                try await engine.prepare()
                Log.app.info("Parakeet ready in the background; switching engine")
                settings.transcriptionEngine = .parakeet
            } catch {
                Log.app.error("Background Parakeet download failed: \(String(describing: error), privacy: .public)")
                lastError = "Parakeet couldn't be downloaded. Dict is still using Apple's engine."
            }
            engine.onProgress = nil
            isDownloadingParakeet = false
        }
    }

    /// True when a hotkey press can begin a recording right now.
    var canStartRecording: Bool {
        isEnabled && !isRecording && !isProcessing && !isPreparingEngine && isEngineReady
    }

    /// Why a hotkey press can't start a recording, for the HUD; nil when
    /// nothing is in the way (or the block is a normal busy state).
    var startBlockedReason: String? {
        if isPreparingEngine { return "Loading speech model…" }
        if !isEngineReady {
            return engineNeedsDownload ? "Download the speech model in Settings" : "Speech model isn't ready"
        }
        return nil
    }

    func startRecording() {
        guard canStartRecording else { return }
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
        let session = processingSession

        processingTask = Task {
            let result = await pipeline.stopRecordingAndProcess()
            // Cancelled with Escape while this was in flight — the HUD and
            // state were already reset, possibly for a newer recording.
            guard session == processingSession else { return }
            processingTask = nil
            isProcessing = false
            onProcessingComplete?(result)
            if result == .failed {
                lastError = "Transcription failed. Please try again."
            }
        }
    }

    /// Abandons an in-flight transcription (Escape) so a hung engine or
    /// formatter can't wedge the app. Cancelling the task stops it before
    /// it inserts anything; if it never returns, it's simply ignored.
    func cancelProcessing() {
        guard isProcessing else { return }
        processingSession += 1
        processingTask?.cancel()
        processingTask = nil
        isProcessing = false
        onProcessingComplete?(.cancelled)
        Log.app.info("Processing cancelled")
    }
}
