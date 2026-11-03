import AppKit
import ApplicationServices

/// Finds the focused UI element of the frontmost app via Accessibility.
enum FocusedElement {
    /// Chromium and Electron apps (Obsidian, Slack, VS Code…) build their
    /// accessibility tree only after a client sets this on the app. Until
    /// then they report no focused text field at all.
    private static let manualAccessibilityAttribute = "AXManualAccessibility" as CFString

    /// Pids already asked to turn their tree on, so we only ask once.
    @MainActor private static var wokenPIDs: Set<pid_t> = []

    /// Asks the frontmost app to expose its accessibility tree. Chromium
    /// builds the tree asynchronously, so call this when dictation starts
    /// to have it ready by the time we read the cursor. Native apps
    /// ignore the attribute.
    @MainActor
    static func prepareFrontmostApp() {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              !wokenPIDs.contains(pid) else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        let result = AXUIElementSetAttributeValue(app, manualAccessibilityAttribute, kCFBooleanTrue)
        // Native apps answer "unsupported"; don't keep asking them either.
        if result == .success || result == .attributeUnsupported {
            wokenPIDs.insert(pid)
        }
    }

    /// The focused element, or nil when the app doesn't expose one. Tries
    /// the system-wide element first, then the frontmost app directly,
    /// which Chromium apps sometimes answer when the system-wide query
    /// fails.
    static func current(timeout: Float = 0.25) -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, timeout)
        if let element = focusedElement(of: systemWide, timeout: timeout) { return element }

        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, timeout)
        return focusedElement(of: app, timeout: timeout)
    }

    private static func focusedElement(of parent: AXUIElement, timeout: Float) -> AXUIElement? {
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else { return nil }
        let focused = focusedRef as! AXUIElement
        AXUIElementSetMessagingTimeout(focused, timeout)
        return focused
    }
}
