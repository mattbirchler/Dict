import SwiftUI
import Sparkle

@main
struct Dict_appApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
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
        appState.permissionChecker.checkAll()

        menuBarManager.setup(appState: appState, updater: updaterController.updater) { [weak self] in
            guard let self else { return }
            self.onboardingController.show(appState: self.appState)
        }

        keyMonitor.onRecordingStart = { [weak self] in
            guard let self else { return }
            self.appState.startRecording()
            self.hudController.show(
                audioLevel: { [weak self] in
                    // Drive the waveform bars from the tail of WhisperKit's
                    // relativeEnergy array. Scale so normal speech pushes the
                    // bars above the bottom without clipping at the top.
                    let energy = self?.appState.pipeline.transcriptionService.audioEnergy ?? []
                    guard let last = energy.last else { return 0 }
                    return min(max(last * 2, 0), 1)
                },
                micName: { StreamingTranscriptionService.inputDeviceName }
            )
        }

        keyMonitor.onRecordingStop = { [weak self] in
            guard let self else { return }
            self.hudController.showProcessing()
            self.appState.stopRecording()
        }

        keyMonitor.onRecordingCancel = { [weak self] in
            guard let self else { return }
            self.appState.cancelRecording()
            self.hudController.dismiss()
        }

        keyMonitor.onHandsFreeChanged = { [weak self] handsFree in
            guard let self else { return }
            if handsFree {
                self.hudController.showHandsFree()
            }
        }

        appState.onProcessingComplete = { [weak self] in
            self?.hudController.dismiss()
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
            appState.preloadWhisperModel()
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
