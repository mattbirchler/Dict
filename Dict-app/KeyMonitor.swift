import CoreGraphics
import Foundation

final class KeyMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var keyDownTime: ContinuousClock.Instant?
    private var isKeyHeld = false
    private var recordingStarted = false
    private var handsFreeMode = false

    var onRecordingStart: (() -> Void)?
    var onRecordingStop: (() -> Void)?
    /// Fired instead of onRecordingStop when the key is released before
    /// holdThreshold — the recording should be discarded, not transcribed.
    var onRecordingCancel: (() -> Void)?
    var onHandsFreeChanged: ((Bool) -> Void)?

    private static let rightCommandKeycode: Int64 = 54
    private static let rightControlKeycode: Int64 = 62
    private static let spaceKeycode: Int64 = 49
    /// Recording starts immediately on key-down so no speech is lost;
    /// releases shorter than this count as accidental taps and cancel it.
    private static let holdThreshold: Duration = .milliseconds(150)

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
        keyDownTime = nil
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        eventTap = nil
        runLoopSource = nil
        isKeyHeld = false
        recordingStarted = false
        handsFreeMode = false
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

        // Spacebar while recording: toggle hands-free mode
        if type == .keyDown && keycode == spaceKeycode {
            Task { @MainActor in
                monitor.handleSpacebar()
            }
            // Only swallow the spacebar if we're actively recording
            if monitor.recordingStarted && !monitor.handsFreeMode {
                return nil
            }
            return Unmanaged.passUnretained(event)
        }

        // Only handle right command / right control for flagsChanged
        guard keycode == rightCommandKeycode || keycode == rightControlKeycode else {
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags

        let isRightCommandDown = keycode == rightCommandKeycode &&
            flags.contains(.maskCommand)
        let isRightControlDown = keycode == rightControlKeycode &&
            flags.contains(.maskControl)
        let isDown = isRightCommandDown || isRightControlDown

        Task { @MainActor in
            if isDown && !monitor.isKeyHeld {
                monitor.handleKeyDown()
            } else if !isDown && monitor.isKeyHeld {
                monitor.handleKeyUp()
            }
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleKeyDown() {
        // If in hands-free mode, right command stops recording
        if handsFreeMode {
            handsFreeMode = false
            recordingStarted = false
            onHandsFreeChanged?(false)
            onRecordingStop?()
            return
        }

        isKeyHeld = true
        recordingStarted = true
        keyDownTime = ContinuousClock().now
        onRecordingStart?()
    }

    private func handleKeyUp() {
        isKeyHeld = false

        // If hands-free mode is active, keep recording
        if handsFreeMode {
            return
        }

        guard recordingStarted else { return }
        recordingStarted = false

        let heldLongEnough = keyDownTime.map {
            ContinuousClock().now - $0 >= Self.holdThreshold
        } ?? true
        keyDownTime = nil

        if heldLongEnough {
            onRecordingStop?()
        } else {
            onRecordingCancel?()
        }
    }

    private func handleSpacebar() {
        // Only activate hands-free if currently recording by holding the key
        guard recordingStarted, isKeyHeld, !handsFreeMode else { return }
        handsFreeMode = true
        onHandsFreeChanged?(true)
    }
}
