import CoreGraphics
import Foundation

final class KeyMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var delayedStartWork: DispatchWorkItem?
    private var isKeyHeld = false
    private var recordingStarted = false

    var onRecordingStart: (() -> Void)?
    var onRecordingStop: (() -> Void)?

    private static let rightCommandKeycode: Int64 = 54
    private static let rightControlKeycode: Int64 = 62
    private static let holdThreshold: TimeInterval = 0.3

    func install() -> Bool {
        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)

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
        delayedStartWork?.cancel()
        delayedStartWork = nil
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
    }

    nonisolated private static let eventCallback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passRetained(event) }
        let monitor = Unmanaged<KeyMonitor>.fromOpaque(refcon).takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = monitor.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keycode == rightCommandKeycode || keycode == rightControlKeycode else {
            return Unmanaged.passRetained(event)
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

        return Unmanaged.passRetained(event)
    }

    private func handleKeyDown() {
        isKeyHeld = true
        recordingStarted = false

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isKeyHeld else { return }
            self.recordingStarted = true
            self.onRecordingStart?()
        }
        delayedStartWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdThreshold, execute: work)
    }

    private func handleKeyUp() {
        isKeyHeld = false
        delayedStartWork?.cancel()
        delayedStartWork = nil

        if recordingStarted {
            recordingStarted = false
            onRecordingStop?()
        }
    }
}
