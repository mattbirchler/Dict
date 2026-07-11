import CoreGraphics
import Foundation

extension HotkeyChoice {
    var keycode: Int64 {
        switch self {
        case .rightCommand: 54
        case .rightControl: 62
        case .rightOption: 61
        case .fn: 63
        }
    }

    var flagMask: CGEventFlags {
        switch self {
        case .rightCommand: .maskCommand
        case .rightControl: .maskControl
        case .rightOption: .maskAlternate
        case .fn: .maskSecondaryFn
        }
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

    var onRecordingStart: (() -> Void)?
    var onRecordingStop: (() -> Void)?
    /// Fired instead of onRecordingStop when the key is released before
    /// holdThreshold — the recording should be discarded, not transcribed.
    var onRecordingCancel: (() -> Void)?
    var onHandsFreeChanged: ((Bool) -> Void)?

    private static let spaceKeycode: Int64 = 49

    func install() -> Bool {
        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)

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

        // Spacebar while holding the hotkey: switch to hands-free mode.
        if type == .keyDown && keycode == spaceKeycode {
            let swallow = monitor.logic.shouldSwallowSpace
            monitor.perform(monitor.logic.spaceDown())
            return swallow ? nil : Unmanaged.passUnretained(event)
        }

        guard keycode == monitor.hotkey.keycode else {
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
            case .start: onRecordingStart?()
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
