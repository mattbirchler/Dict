import Foundation

/// Pure logic for gating and trimming a recording based on per-frame
/// voice-activity flags.
enum VoiceGate {
    /// The frame range spanning first-to-last voice activity, padded on
    /// both sides and clamped to the buffer. Nil when no frame has voice —
    /// the caller should skip transcription entirely.
    static func activeFrameRange(voiceActivity: [Bool], paddingFrames: Int) -> Range<Int>? {
        guard let first = voiceActivity.firstIndex(of: true),
              let last = voiceActivity.lastIndex(of: true) else {
            return nil
        }
        let start = max(0, first - paddingFrames)
        let end = min(voiceActivity.count, last + 1 + paddingFrames)
        return start..<end
    }
}
