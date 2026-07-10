import Foundation

/// Pure decision logic for the dictation hotkey — extracted from KeyMonitor
/// so mode and state transitions can be unit tested without CGEvents.
struct DictationKeyLogic {
    enum Action: Equatable { case start, stop, cancel, enterHandsFree }

    /// Recording starts immediately on key-down so no speech is lost;
    /// hold-mode releases shorter than this count as accidental taps.
    static let holdThreshold: Duration = .milliseconds(150)

    var mode: ActivationMode
    private(set) var isKeyHeld = false
    private(set) var isRecording = false
    private(set) var handsFreeMode = false
    private var keyDownTime: ContinuousClock.Instant?

    init(mode: ActivationMode = .holdToTalk) {
        self.mode = mode
    }

    mutating func hotkeyDown(now: ContinuousClock.Instant = ContinuousClock().now) -> Action? {
        guard !isKeyHeld else { return nil }
        isKeyHeld = true

        switch mode {
        case .holdToTalk:
            if handsFreeMode {
                handsFreeMode = false
                isRecording = false
                return .stop
            }
            isRecording = true
            keyDownTime = now
            return .start
        case .toggle:
            if isRecording {
                isRecording = false
                return .stop
            }
            isRecording = true
            return .start
        }
    }

    mutating func hotkeyUp(now: ContinuousClock.Instant = ContinuousClock().now) -> Action? {
        isKeyHeld = false
        guard mode == .holdToTalk, !handsFreeMode, isRecording else { return nil }

        isRecording = false
        let heldLongEnough = keyDownTime.map { now - $0 >= Self.holdThreshold } ?? true
        keyDownTime = nil
        return heldLongEnough ? .stop : .cancel
    }

    mutating func spaceDown() -> Action? {
        guard mode == .holdToTalk, isRecording, isKeyHeld, !handsFreeMode else { return nil }
        handsFreeMode = true
        return .enterHandsFree
    }

    /// Whether a Space key-down should be swallowed instead of passed to the
    /// frontmost app (it's about to switch us into hands-free mode).
    var shouldSwallowSpace: Bool {
        mode == .holdToTalk && isRecording && !handsFreeMode
    }

    /// Called when the hotkey or mode changes, or monitoring stops. Returns
    /// .stop if a recording was in flight so the owner can finish it cleanly.
    mutating func reset() -> Action? {
        let wasRecording = isRecording
        isKeyHeld = false
        isRecording = false
        handsFreeMode = false
        keyDownTime = nil
        return wasRecording ? .stop : nil
    }
}
