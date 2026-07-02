import Foundation
import WhisperKit

/// Drops Whisper segments that are likely silence hallucinations ("Thank
/// you.", "Thanks for watching!", …). Two layered rules, both deliberately
/// stricter than Whisper's built-in AND of noSpeechProb and avgLogprob,
/// which confident hallucinations slip through.
struct TranscriptFilter {
    /// Segments with noSpeechProb above this are dropped outright.
    var noSpeechThreshold: Float = 0.5
    /// Blocklisted phrases are dropped when less than this fraction of
    /// their audio frames contain voice activity.
    var minVoicedFraction: Float = 0.2

    /// Phrases Whisper is known to decode from silence, in normalized form.
    static let hallucinationPhrases: Set<String> = [
        "thank you", "thanks", "thank you very much", "thank you so much",
        "thanks for watching", "thank you for watching",
        "thanks for listening", "thank you for listening",
        "see you next time", "see you in the next video",
        "bye", "bye bye", "goodbye",
        "the end", "you", "so", "subscribe", "please subscribe",
    ]

    /// - Parameters:
    ///   - segments: Whisper output; times are relative to the audio that
    ///     was transcribed.
    ///   - voiceActivity: per-frame VAD flags for that same audio.
    ///   - frameDuration: seconds per VAD frame.
    func filteredText(
        segments: [TranscriptionSegment],
        voiceActivity: [Bool],
        frameDuration: Float
    ) -> String {
        segments
            .filter { keep($0, voiceActivity: voiceActivity, frameDuration: frameDuration) }
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func keep(
        _ segment: TranscriptionSegment,
        voiceActivity: [Bool],
        frameDuration: Float
    ) -> Bool {
        if segment.noSpeechProb > noSpeechThreshold {
            print("[Filter] Dropped (noSpeechProb \(segment.noSpeechProb)): \"\(segment.text)\"")
            return false
        }
        let normalized = Self.normalize(segment.text)
        if normalized.isEmpty { return false }
        if Self.hallucinationPhrases.contains(normalized) {
            let voiced = voicedFraction(
                start: segment.start,
                end: segment.end,
                voiceActivity: voiceActivity,
                frameDuration: frameDuration
            )
            if voiced < minVoicedFraction {
                print("[Filter] Dropped (blocklist, voiced \(voiced)): \"\(segment.text)\"")
                return false
            }
        }
        return true
    }

    /// Lowercased, punctuation stripped, whitespace collapsed — the form
    /// used for blocklist matching.
    static func normalize(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Fraction of VAD frames overlapping [start, end] that contain voice.
    private func voicedFraction(
        start: Float,
        end: Float,
        voiceActivity: [Bool],
        frameDuration: Float
    ) -> Float {
        guard frameDuration > 0, !voiceActivity.isEmpty, end > start else { return 0 }
        let first = max(0, Int(start / frameDuration))
        let last = min(voiceActivity.count - 1, Int((end / frameDuration).rounded(.up)) - 1)
        guard first <= last else { return 0 }
        let window = voiceActivity[first...last]
        return Float(window.count(where: { $0 })) / Float(window.count)
    }
}
