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
    /// Mirrors "a model download is running" so the status icon and the menu
    /// can show it. Kept as stored state (rather than reading AppState in
    /// menuNeedsUpdate only) because the icon must also update while the
    /// menu is closed.
    private var isDownloadingModel = false
    private var downloadPercent = 0

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
        observeDownloadState()
    }

    // MARK: - Model-download indicator

    /// Re-registers observation of AppState's download mirror so the status
    /// icon reflects an in-flight model download even while the menu is
    /// closed. `withObservationTracking` fires its onChange once, so each
    /// change re-arms the observation after refreshing.
    private func observeDownloadState() {
        guard let appState else { return }
        withObservationTracking {
            _ = appState.isPreparingEngine
            _ = appState.engineNeedsDownload
            _ = appState.engineDownloadProgress
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.refreshDownloadIndicator()
                self.observeDownloadState()
            }
        }
        refreshDownloadIndicator()
    }

    private func refreshDownloadIndicator() {
        guard let appState, let button = statusItem?.button else { return }
        let downloading = appState.isPreparingEngine && appState.engineNeedsDownload
        let percent = min(100, max(0, Int(appState.engineDownloadProgress * 100)))
        guard downloading != isDownloadingModel || (downloading && percent != downloadPercent) else {
            return
        }
        isDownloadingModel = downloading
        downloadPercent = percent

        if downloading {
            button.image = NSImage(
                systemSymbolName: "arrow.down.circle",
                accessibilityDescription: "Dict: downloading speech model"
            )
            button.toolTip = "Downloading speech model: \(percent)%"
        } else {
            button.image = NSImage(
                systemSymbolName: "waveform",
                accessibilityDescription: "Dict"
            )
            button.toolTip = nil
        }
    }

    /// Rebuilt each time the menu opens, so the Dictation-Enabled checkmark and
    /// the permission item always reflect current state.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let appState else { return }

        if isDownloadingModel {
            let downloading = NSMenuItem(
                title: "Downloading speech model: \(downloadPercent)%",
                action: nil,
                keyEquivalent: ""
            )
            downloading.isEnabled = false
            menu.addItem(downloading)
            menu.addItem(.separator())
        }

        let enabled = NSMenuItem(
            title: "Dictation Enabled",
            action: #selector(toggleEnabled),
            keyEquivalent: ""
        )
        enabled.target = self
        enabled.state = appState.isEnabled ? .on : .off
        menu.addItem(enabled)

        menu.addItem(.separator())

        if !appState.permissionChecker.requiredGranted(for: appState.settings.transcriptionEngine) {
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
