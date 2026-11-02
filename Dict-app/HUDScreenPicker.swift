import AppKit
import ApplicationServices

/// Chooses which display the HUD appears on: the one holding the window
/// being dictated into, else the one under the mouse, else the first.
enum HUDScreenPicker {
    /// Index into `screens` (AppKit coordinates), or nil when there are none.
    static func pick(screens: [CGRect], focusedWindow: CGRect?, mouse: CGPoint) -> Int? {
        guard !screens.isEmpty else { return nil }
        if let focusedWindow {
            let center = CGPoint(x: focusedWindow.midX, y: focusedWindow.midY)
            if let index = screens.firstIndex(where: { $0.contains(center) }) { return index }
        }
        if let index = screens.firstIndex(where: { $0.contains(mouse) }) { return index }
        return 0
    }

    /// The frontmost app's focused window, in AppKit coordinates, via
    /// Accessibility. Nil when the app has no focused window or doesn't
    /// answer within a quarter second.
    @MainActor
    static func focusedWindowFrame() -> CGRect? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.25)

        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let windowRef, CFGetTypeID(windowRef) == AXUIElementGetTypeID() else { return nil }
        let window = windowRef as! AXUIElement
        AXUIElementSetMessagingTimeout(window, 0.25)

        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionRef, let sizeRef else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionRef as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) else { return nil }

        // Accessibility measures from the top-left of the primary display;
        // AppKit from its bottom-left.
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return nil }
        return CGRect(x: position.x, y: primaryHeight - position.y - size.height, width: size.width, height: size.height)
    }
}
