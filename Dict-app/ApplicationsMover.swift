import AppKit
import os

/// Offers to move Dict into /Applications when it was launched from
/// somewhere else (Downloads, a disk image). macOS ties the Accessibility
/// permission to the app's location, and Sparkle needs a writable, stable
/// path, so running from Downloads breaks both after the first update.
enum ApplicationsMover {
    /// Whether to offer the move. Debug builds, installed copies, and
    /// Xcode build products are left alone.
    static func shouldOffer(bundlePath: String, isDebugBuild: Bool, homeDirectory: String) -> Bool {
        guard !isDebugBuild else { return false }
        if bundlePath.hasPrefix("/Applications/") { return false }
        if bundlePath.hasPrefix(homeDirectory + "/Applications/") { return false }
        if bundlePath.contains("/DerivedData/") { return false }
        return true
    }

    /// Asks, moves, and relaunches from /Applications. Returns true when a
    /// move is underway and this process is about to quit, so the caller
    /// should stop setting up; false when nothing happened.
    @MainActor
    static func offerIfNeeded() -> Bool {
        #if DEBUG
        let isDebugBuild = true
        #else
        let isDebugBuild = false
        #endif
        let bundleURL = Bundle.main.bundleURL
        guard shouldOffer(bundlePath: bundleURL.path, isDebugBuild: isDebugBuild, homeDirectory: NSHomeDirectory()) else {
            return false
        }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Move Dict to the Applications folder?"
        alert.informativeText = "Dict needs to stay in one place so macOS can remember its Accessibility permission and install updates."
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")
        guard alert.runModal() == .alertFirstButtonReturn else { return false }

        do {
            try move(from: bundleURL)
            return true
        } catch {
            Log.app.error("Move to Applications failed: \(String(describing: error), privacy: .public)")
            let failure = NSAlert()
            failure.messageText = "Couldn't move Dict"
            failure.informativeText = "\(error.localizedDescription)\n\nYou can drag Dict to your Applications folder yourself."
            failure.runModal()
            return false
        }
    }

    private static func move(from source: URL) throws {
        let fileManager = FileManager.default
        let destination = URL(fileURLWithPath: "/Applications").appendingPathComponent(source.lastPathComponent)

        if fileManager.fileExists(atPath: destination.path) {
            // Another copy is installed. Quit it if it's running, then replace it.
            let bundleID = Bundle.main.bundleIdentifier ?? ""
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            where app.bundleURL == destination && app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                app.terminate()
            }
            try fileManager.trashItem(at: destination, resultingItemURL: nil)
        }
        try fileManager.copyItem(at: source, to: destination)
        Log.app.info("Moved to \(destination.path, privacy: .public)")

        // A disk image is read-only; leave the original there.
        if fileManager.isWritableFile(atPath: source.deletingLastPathComponent().path) {
            try? fileManager.trashItem(at: source, resultingItemURL: nil)
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: destination, configuration: configuration) { _, error in
            Task { @MainActor in
                if let error {
                    Log.app.error("Relaunch from Applications failed: \(String(describing: error), privacy: .public)")
                    let alert = NSAlert()
                    alert.messageText = "Dict was moved to Applications"
                    alert.informativeText = "It couldn't be reopened automatically. Open Dict from your Applications folder."
                    alert.runModal()
                }
                NSApp.terminate(nil)
            }
        }
    }
}
