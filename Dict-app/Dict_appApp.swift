import SwiftUI

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
    let appState = AppState()
    let menuBarManager = MenuBarManager()
    let hudController = HUDPanelController()
    let keyMonitor = KeyMonitor()
    let onboardingController = OnboardingWindowController()
    private var permissionCheckTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        appState.permissionChecker.checkAll()

        menuBarManager.setup(appState: appState) { [weak self] in
            guard let self else { return }
            self.onboardingController.show(appState: self.appState)
        }

        keyMonitor.onRecordingStart = { [weak self] in
            guard let self else { return }
            self.appState.startRecording()
            self.hudController.show(
                audioLevel: { [weak self] in self?.appState.pipeline.audioRecorder.currentLevel ?? 0 },
                micName: { [weak self] in self?.appState.pipeline.audioRecorder.inputDeviceName ?? "Unknown" }
            )
        }

        keyMonitor.onRecordingStop = { [weak self] in
            guard let self else { return }
            self.hudController.dismiss()
            self.appState.stopRecording()
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
