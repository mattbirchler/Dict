import SwiftUI
import Sparkle
import os

@main
struct Dict_appApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // The real Settings UI is presented by SettingsWindowController (an
        // AppKit window), because the menu-bar popover lives outside the
        // SwiftUI scene graph and can't open a `Settings` scene. This scene
        // exists only to satisfy the App's scene requirement.
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    // --sample-stats previews use default settings, not the real ones.
    let appState = AppState(settings: SettingsStore(defaults: HUDPreview.sampleStatsDefaults() ?? .standard))
    let menuBarManager = MenuBarManager()
    let hudController = HUDPanelController()
    let keyMonitor = KeyMonitor()
    let onboardingController = OnboardingWindowController()
    let mainWindowController = MainWindowController()
    private var permissionCheckTimer: Timer?
    /// The License screen opens by itself the first time an expired trial
    /// blocks the hotkey, not on every press.
    private var showedTrialEnded = false

    // Sparkle updater — starts on launch, runs automatic daily checks
    // (controlled by SUEnableAutomaticChecks / SUScheduledCheckInterval in
    // Info.plist, which default to on / 24h for menu bar apps).
    let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ApplicationsMover.offerIfNeeded() { return }
        SoundPlayer.isMuted = CommandLine.arguments.contains { $0.hasPrefix("--preview-") }
        if HUDPreview.renderHUD() { exit(0) }
        if HUDPreview.present(in: hudController) { return }
        if HUDPreview.presentWindow(show: { [self] section in
            mainWindowController.show(section: section, appState: appState, updater: updaterController.updater)
            return mainWindowController.windowNumber
        }) { return }
        if HUDPreview.presentOnboarding(show: { [self] step in
            onboardingController.show(appState: appState, startingAt: step)
            return onboardingController.windowNumber
        }) { return }

        // Screenshot runs use made-up stats and shouldn't count as usage.
        let isSampleRun = CommandLine.arguments.contains("--sample-stats")
        Analytics.shared.setup(enabled: appState.settings.sharesUsageData && !isSampleRun, launchProperties: [
            "engine": appState.settings.transcriptionEngine.rawValue,
            "style": appState.settings.dictationStyle.rawValue,
            "license": Analytics.licenseStatusName(appState.license.status),
        ])

        hudController.colorScheme = appState.settings.hudColorScheme
        appState.onHUDColorSchemeChanged = { [weak self] scheme in self?.hudController.colorScheme = scheme }
        appState.onEngineReady = { [weak self] in
            guard let self, self.appState.isEnabled else { return }
            self.hudController.showReady(hotkeyGlyph: self.appState.settings.hotkey.glyph)
        }
        appState.permissionChecker.checkAll()

        menuBarManager.setup(
            appState: appState,
            onOpen: { [weak self] section in
                guard let self else { return }
                self.mainWindowController.show(
                    section: section,
                    appState: self.appState,
                    updater: self.updaterController.updater
                )
            },
            onShowOnboarding: { [weak self] in
                guard let self else { return }
                self.onboardingController.show(appState: self.appState)
            },
            onCheckForUpdates: { [weak self] in
                self?.updaterController.updater.checkForUpdates()
            }
        )

        keyMonitor.onRecordingStart = { [weak self] in
            guard let self else { return false }
            guard self.appState.canStartRecording else {
                // A missing engine gets a notice; a busy state (already
                // recording or processing) leaves the HUD as it is.
                if let reason = self.appState.startBlockedReason {
                    self.hudController.showNotice(reason)
                }
                if !self.appState.license.status.allowsDictation && !self.showedTrialEnded {
                    self.showedTrialEnded = true
                    self.openMainWindow(.license)
                }
                return false
            }
            self.appState.startRecording()
            SoundPlayer.play(.start)
            self.hudController.show(
                audioSpectrum: { [weak self] in
                    self?.appState.pipeline.activeEngine.audioSpectrum ?? []
                },
                micName: { [weak self] in self?.appState.pipeline.currentInputDevice?.name ?? "Microphone" },
                liveTranscript: { [weak self] in
                    self?.appState.pipeline.activeEngine.liveTranscript ?? LiveTranscript()
                },
                hotkeyGlyph: self.appState.settings.hotkey.glyph
            )
            if self.appState.settings.showsLiveWords {
                let engine = self.appState.pipeline.activeEngine
                if engine.supportsLiveTranscript {
                    engine.beginLivePreview()
                    self.hudController.showLiveWords()
                }
            }
            return true
        }

        keyMonitor.onRecordingStop = { [weak self] in
            // A press that was blocked (engine loading) never started a
            // recording, so its release must not leave a processing pill up.
            guard let self, self.appState.isRecording else { return }
            SoundPlayer.play(.stop)
            self.hudController.showProcessing()
            self.appState.stopRecording()
        }

        keyMonitor.onRecordingCancel = { [weak self] in
            guard let self, self.appState.isRecording else { return }
            self.appState.cancelRecording()
            self.hudController.dismiss()
        }

        keyMonitor.isProcessing = { [weak self] in
            self?.appState.isProcessing ?? false
        }

        keyMonitor.onProcessingCancel = { [weak self] in
            self?.appState.cancelProcessing()
        }

        keyMonitor.onHandsFreeChanged = { [weak self] handsFree in
            guard let self, self.appState.isRecording else { return }
            if handsFree {
                let engine = self.appState.pipeline.activeEngine
                engine.beginLivePreview()
                self.hudController.showHandsFree(livePreview: engine.supportsLiveTranscript)
            }
        }

        appState.onProcessingComplete = { [weak self] result in
            if case .inserted = result { SoundPlayer.play(.inserted) }
            self?.hudController.finish(result: result)
        }

        keyMonitor.hotkey = appState.settings.hotkey
        keyMonitor.activationMode = appState.settings.activationMode
        appState.onHotkeySettingsChanged = { [weak self] in
            guard let self else { return }
            self.keyMonitor.hotkey = self.appState.settings.hotkey
            self.keyMonitor.activationMode = self.appState.settings.activationMode
        }

        if appState.permissionChecker.accessibilityGranted && appState.isEnabled {
            _ = keyMonitor.install()
        }

        appState.onAccessibilityGranted = { [weak self] in
            guard let self, self.appState.isEnabled else { return }
            _ = self.keyMonitor.install()
        }

        appState.onEnabledChanged = { [weak self] enabled in
            guard let self else { return }
            if enabled && self.appState.permissionChecker.accessibilityGranted {
                _ = self.keyMonitor.install()
            } else {
                self.keyMonitor.uninstall()
            }
        }

        if !appState.hasCompletedOnboarding {
            onboardingController.show(appState: appState)
        } else {
            appState.prepareEngine()
        }

        // Opened from a link before launch finished: act on it now.
        didFinishLaunching = true
        if let pending = pendingActivationURL {
            pendingActivationURL = nil
            handleActivation(pending)
        }

        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let wasGranted = self.appState.permissionChecker.accessibilityGranted
            self.appState.permissionChecker.checkAll()
            if !wasGranted && self.appState.permissionChecker.accessibilityGranted {
                _ = self.keyMonitor.install()
            }
        }
    }

    // MARK: - License links

    private var didFinishLaunching = false
    private var pendingActivationURL: URL?

    private func openMainWindow(_ section: MainSection) {
        mainWindowController.show(section: section, appState: appState, updater: updaterController.updater)
    }

    /// dictapp://activate?key=… from the purchase confirmation page.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first(where: { $0.scheme == "dictapp" && $0.host == "activate" }) else { return }
        if didFinishLaunching {
            handleActivation(url)
        } else {
            pendingActivationURL = url
        }
    }

    private func handleActivation(_ url: URL) {
        do {
            try appState.license.activate(url.absoluteString)
            Log.app.info("Activated a license from a link")
        } catch {
            appState.license.linkProblem = error.message
            Log.app.error("Activation link rejected")
        }
        openMainWindow(.license)
    }
}
