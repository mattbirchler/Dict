import AppKit
import SwiftUI
import Sparkle

/// Presents the app's main window (History + Settings sidebar) from AppKit,
/// mirroring OnboardingWindowController.
///
/// The status-item menu is a native NSMenu (not a SwiftUI scene), so the window
/// is owned and shown here rather than via a SwiftUI `Settings`/`Window` scene.
/// This is the same pattern OnboardingWindowController uses successfully.
final class MainWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let model = MainWindowModel()

    func show(section: MainSection, appState: AppState, updater: SPUUpdater) {
        model.section = section

        // Already open — switch section (done above) and bring it forward.
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingController = NSHostingController(
            rootView: MainWindow(appState: appState, updater: updater, model: model)
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Dict"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 720, height: 460))
        window.setFrameAutosaveName("DictMainWindow")
        window.center()
        // We own the window's lifetime (cleared in windowWillClose), so don't
        // let AppKit release it out from under us on close.
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
