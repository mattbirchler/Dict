import Foundation

/// What an engine has heard so far while recording, shown in the expanded
/// hands-free HUD. A preview only: the inserted text still comes from the
/// engine's final pass at stop().
struct LiveTranscript: Equatable {
    /// Words unlikely to change.
    var confirmed = ""
    /// The most recent words, which may still be revised.
    var tentative = ""

    var isEmpty: Bool { confirmed.isEmpty && tentative.isEmpty }

    var fullText: String {
        [confirmed, tentative].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Splits a fresh decode of the whole recording against the previous
    /// one: the leading words both decodes agree on are confirmed, the rest
    /// is tentative. Comparison ignores case and punctuation, which the
    /// model often revises as more context arrives.
    static func comparing(previous: String, current: String) -> LiveTranscript {
        let previousWords = previous.split(whereSeparator: \.isWhitespace).map { normalized($0) }
        let currentWords = current.split(whereSeparator: \.isWhitespace)
        var agreed = 0
        while agreed < min(previousWords.count, currentWords.count),
              previousWords[agreed] == normalized(currentWords[agreed]) {
            agreed += 1
        }
        return LiveTranscript(
            confirmed: currentWords[..<agreed].joined(separator: " "),
            tentative: currentWords[agreed...].joined(separator: " ")
        )
    }

    private static func normalized(_ word: Substring) -> String {
        String(word.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }
}
