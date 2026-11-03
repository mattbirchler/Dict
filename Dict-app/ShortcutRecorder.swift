import AppKit
import SwiftUI

/// A button that shows the dictation key and, when clicked, listens for
/// the next key press and makes it the hotkey. A plain modifier key
/// (right Command and friends) picks that preset; any other key with its
/// held modifiers becomes a custom combo. Escape stops listening.
struct ShortcutRecorder: View {
    @Binding var hotkey: HotkeyChoice
    @State private var isListening = false
    @State private var heldModifiers: UInt64 = 0
    @State private var monitor: Any?

    /// True while any recorder is listening, so other key handlers stand down.
    nonisolated(unsafe) static var isRecording = false

    private static let presetKeycodes: [UInt16: HotkeyChoice] = [54: .rightCommand, 61: .rightOption, 62: .rightControl, 63: .fn]
    private static let modifierKeycodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    var body: some View {
        Button {
            isListening ? stop() : start()
        } label: {
            HStack(spacing: 6) {
                if isListening {
                    Image(systemName: "record.circle")
                        .foregroundStyle(.red)
                    Text(heldModifiers == 0 ? "Press keys…" : HotkeyChoice.modifierGlyphs(heldModifiers) + "…")
                } else {
                    Text(hotkey.glyph)
                        .fontWeight(.semibold)
                }
            }
            .frame(minWidth: 96)
        }
        .buttonStyle(.bordered)
        .help(isListening ? "Press the key or combination you want. Escape cancels." : "Click, then press a key")
        .onDisappear { stop() }
    }

    private func start() {
        isListening = true
        heldModifiers = 0
        Self.isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            handle(event)
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isListening = false
        heldModifiers = 0
        Self.isRecording = false
    }

    /// Returns nil when the event was consumed.
    private func handle(_ event: NSEvent) -> NSEvent? {
        let modifiers = UInt64(event.modifierFlags.rawValue) & HotkeyChoice.modifierMask
        switch event.type {
        case .flagsChanged:
            heldModifiers = modifiers
            // A modifier pressed on its own, then released: that's a preset.
            if modifiers == 0, let preset = Self.presetKeycodes[event.keyCode] {
                hotkey = preset
                stop()
            }
            return nil
        case .keyDown:
            if event.keyCode == 53 { // Escape
                stop()
                return nil
            }
            guard !Self.modifierKeycodes.contains(event.keyCode) else { return nil }
            hotkey = .custom(keycode: Int64(event.keyCode), modifiers: modifiers, label: Self.label(for: event))
            stop()
            return nil
        default:
            return event
        }
    }

    /// A readable name for the key that was pressed.
    static func label(for event: NSEvent) -> String {
        if let name = specialKeyNames[event.keyCode] { return name }
        let chars = event.charactersIgnoringModifiers ?? ""
        if let scalar = chars.unicodeScalars.first, scalar.value >= 0xF700, scalar.value <= 0xF8FF {
            return "Key \(event.keyCode)"
        }
        return chars.isEmpty ? "Key \(event.keyCode)" : chars.uppercased()
    }

    static let specialKeyNames: [UInt16: String] = [
        49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 117: "Forward Delete", 76: "Enter",
        123: "←", 124: "→", 125: "↓", 126: "↑", 115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9",
        109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17",
        79: "F18", 80: "F19", 90: "F20", 71: "Clear", 81: "=", 75: "/", 67: "*", 78: "-", 69: "+",
    ]
}
