import Foundation

/// How a dictation ended once the hotkey was released.
enum DictationResult: Equatable {
    /// Text was transcribed and pasted into the frontmost app.
    case inserted(String)
    /// The engine heard no words (silence, or a recording too short to decode).
    case nothingHeard
    /// The engine or formatter failed.
    case failed
    /// The person pressed Escape or switched engines mid-flight.
    case cancelled

    /// What the HUD says for results that produced no text; nil when
    /// nothing needs saying.
    var hudMessage: String? {
        switch self {
        case .inserted, .cancelled: nil
        case .nothingHeard: "Nothing heard"
        case .failed: "Couldn't transcribe. Try again."
        }
    }
}
