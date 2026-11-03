import SwiftUI
import Sparkle

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
    let appState = AppState(settings: SettingsStore())
    let menuBarManager = MenuBarManager()
    let hudController = HUDPanelController()
    let keyMonitor = KeyMonitor()
    let onboardingController = OnboardingWindowController()
    let mainWindowController = MainWindowController()
    private var permissionCheckTimer: Timer?

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
        if HUDPreview.present(in: hudController) { return }

        hudController.colorScheme = appState.settings.hudColorScheme
        appState.onHUDColorSchemeChanged = { [weak self] scheme in self?.hudController.colorScheme = scheme }
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
                return false
            }
            self.appState.startRecording()
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
            return true
        }

        keyMonitor.onRecordingStop = { [weak self] in
            // A press that was blocked (engine loading) never started a
            // recording, so its release must not leave a processing pill up.
            guard let self, self.appState.isRecording else { return }
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

        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let wasGranted = self.appState.permissionChecker.accessibilityGranted
            self.appState.permissionChecker.checkAll()
            if !wasGranted && self.appState.permissionChecker.accessibilityGranted {
                _ = self.keyMonitor.install()
            }
        }
    }
}
