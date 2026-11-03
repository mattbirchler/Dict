import CoreGraphics
import Foundation

extension HotkeyChoice {
    /// Keycode of the physical key. Presets are modifier keys watched via
    /// flagsChanged; custom combos are ordinary keys watched via keyDown.
    var keycode: Int64 {
        switch self {
        case .rightCommand: 54
        case .rightControl: 62
        case .rightOption: 61
        case .fn: 63
        case .custom(let keycode, _, _): keycode
        }
    }

    var flagMask: CGEventFlags {
        switch self {
        case .rightCommand: .maskCommand
        case .rightControl: .maskControl
        case .rightOption: .maskAlternate
        case .fn: .maskSecondaryFn
        case .custom(_, let modifiers, _): CGEventFlags(rawValue: modifiers)
        }
    }

    /// Whether a keyDown of `keycode` with `flags` is this custom combo.
    /// Presets never match here; they are driven by flagsChanged.
    func matchesKeyDown(keycode: Int64, flags: CGEventFlags) -> Bool {
        guard case .custom(let key, let modifiers, _) = self else { return false }
        return keycode == key && (flags.rawValue & HotkeyChoice.modifierMask) == modifiers
    }
}

final class KeyMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// All state transitions live in the pure logic struct. The event tap
    /// callback runs on the main run loop (see install()), so access is
    /// single-threaded even though this class isn't actor-isolated.
    private var logic = DictationKeyLogic()

    var hotkey: HotkeyChoice = .rightCommand {
        didSet { resetLogic() }
    }

    var activationMode: ActivationMode {
        get { logic.mode }
        set {
            resetLogic()
            logic.mode = newValue
        }
    }

    /// Returns whether a recording actually began; false means the app
    /// refused (engine loading) and the key logic forgets the press.
    var onRecordingStart: (() -> Bool)?
    var onRecordingStop: (() -> Void)?
    /// Fired instead of onRecordingStop when the key is released before
    /// holdThreshold — the recording should be discarded, not transcribed.
    var onRecordingCancel: (() -> Void)?
    var onHandsFreeChanged: ((Bool) -> Void)?
    /// Whether a transcription is in flight, so Escape knows to cancel it.
    var isProcessing: (() -> Bool)?
    /// Fired when Escape is pressed while a transcription is in flight.
    var onProcessingCancel: (() -> Void)?

    private static let spaceKeycode: Int64 = 49
    private static let escapeKeycode: Int64 = 53

    func install() -> Bool {
        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: KeyMonitor.eventCallback,
            userInfo: refcon
        ) else {
            return false
        }

        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func uninstall() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        eventTap = nil
        runLoopSource = nil
        _ = logic.reset()
    }

    nonisolated private static let eventCallback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let monitor = Unmanaged<KeyMonitor>.fromOpaque(refcon).takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = monitor.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let keycode = event.getIntegerValueField(.keyboardEventKeycode)

        // A recorded combo (say ⌥Space) is an ordinary key: press starts,
        // release ends, and the app underneath never sees it. Checked first
        // so a combo built on Space or Escape wins over their other jobs.
        if monitor.hotkey.isCustom {
            if type == .keyDown && monitor.hotkey.matchesKeyDown(keycode: keycode, flags: event.flags) {
                if !monitor.logic.isKeyHeld { monitor.perform(monitor.logic.hotkeyDown()) }
                return nil
            }
            if type == .keyUp && keycode == monitor.hotkey.keycode && monitor.logic.isKeyHeld {
                monitor.perform(monitor.logic.hotkeyUp())
                return nil
            }
        }

        // Escape cancels a recording, or a transcription that's in flight.
        // Swallowed only when it did something.
        if type == .keyDown && keycode == escapeKeycode {
            if let action = monitor.logic.escapeDown() {
                monitor.perform(action)
                return nil
            }
            let processing = MainActor.assumeIsolated { monitor.isProcessing?() ?? false }
            if processing {
                MainActor.assumeIsolated { monitor.onProcessingCancel?() }
                return nil
            }
            return Unmanaged.passUnretained(event)
        }

        // Spacebar while holding the hotkey: switch to hands-free mode.
        if type == .keyDown && keycode == spaceKeycode {
            let swallow = monitor.logic.shouldSwallowSpace
            monitor.perform(monitor.logic.spaceDown())
            return swallow ? nil : Unmanaged.passUnretained(event)
        }

        guard type == .flagsChanged, !monitor.hotkey.isCustom, keycode == monitor.hotkey.keycode else {
            return Unmanaged.passUnretained(event)
        }

        let isDown = event.flags.contains(monitor.hotkey.flagMask)
        if isDown && !monitor.logic.isKeyHeld {
            monitor.perform(monitor.logic.hotkeyDown())
        } else if !isDown && monitor.logic.isKeyHeld {
            monitor.perform(monitor.logic.hotkeyUp())
        }

        return Unmanaged.passUnretained(event)
    }

    private func perform(_ action: DictationKeyLogic.Action?) {
        guard let action else { return }
        // The event-tap callback and resetLogic() both run on the main thread
        // (the tap's run-loop source is on the main run loop), so deliver the
        // callback synchronously on the main actor. This also guarantees a
        // synchronous .start-then-.stop pair (fast hold-release) fires in order,
        // which separate unstructured Tasks would not.
        MainActor.assumeIsolated {
            switch action {
            case .start:
                if onRecordingStart?() == false { logic.abandonStart() }
            case .stop: onRecordingStop?()
            case .cancel: onRecordingCancel?()
            case .enterHandsFree: onHandsFreeChanged?(true)
            }
        }
    }

    /// Hotkey or mode changed. If a recording is in flight, finish it
    /// cleanly (transcribe what was said) before adopting the new config.
    private func resetLogic() {
        perform(logic.reset())
    }
}
