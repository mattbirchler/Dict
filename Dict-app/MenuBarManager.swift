import AppKit

/// Owns the status-bar item and its native NSMenu. A native menu (rather than
/// an NSHostingController-in-NSPopover) focuses correctly on first click and
/// feels native — the popover did neither. Quick actions live here; the richer
/// UI (history, settings) opens in the main window.
final class MenuBarManager: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var appState: AppState?
    private var onOpen: ((MainSection) -> Void)?
    private var onShowOnboarding: (() -> Void)?
    private var onCheckForUpdates: (() -> Void)?

    func setup(
        appState: AppState,
        onOpen: @escaping (MainSection) -> Void,
        onShowOnboarding: @escaping () -> Void,
        onCheckForUpdates: @escaping () -> Void
    ) {
        self.appState = appState
        self.onOpen = onOpen
        self.onShowOnboarding = onShowOnboarding
        self.onCheckForUpdates = onCheckForUpdates

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "waveform",
            accessibilityDescription: "Dict"
        )

        let menu = NSMenu()
        menu.delegate = self
        // Assigning a menu makes the status item present it natively on click.
        statusItem.menu = menu

        self.statusItem = statusItem
    }

    /// Rebuilt each time the menu opens, so the Dictation-Enabled checkmark and
    /// the permission item always reflect current state.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let appState else { return }

        let enabled = NSMenuItem(
            title: "Dictation Enabled",
            action: #selector(toggleEnabled),
            keyEquivalent: ""
        )
        enabled.target = self
        enabled.state = appState.isEnabled ? .on : .off
        menu.addItem(enabled)

        menu.addItem(.separator())

        if !appState.permissionChecker.allGranted {
            let fix = NSMenuItem(
                title: "Fix Permissions…",
                action: #selector(showOnboarding),
                keyEquivalent: ""
            )
            fix.target = self
            menu.addItem(fix)
        }

        let history = NSMenuItem(
            title: "History…",
            action: #selector(openHistory),
            keyEquivalent: ""
        )
        history.target = self
        menu.addItem(history)

        let settings = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let updates = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        updates.target = self
        menu.addItem(updates)

        let quit = NSMenuItem(
            title: "Quit Dict",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func toggleEnabled() {
        appState?.isEnabled.toggle()
    }

    @objc private func showOnboarding() {
        onShowOnboarding?()
    }

    @objc private func openHistory() {
        onOpen?(.history)
    }

    @objc private func openSettings() {
        onOpen?(.general)
    }

    @objc private func checkForUpdates() {
        onCheckForUpdates?()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
