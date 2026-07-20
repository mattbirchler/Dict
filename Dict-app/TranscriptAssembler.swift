import Foundation

/// Joins independently decoded chunks back into one transcript.
///
/// Each chunk is decoded with the previous chunk's tail as a decoder prompt,
/// which sometimes makes Whisper re-emit that tail. This strips the
/// duplicate so the seam reads naturally.
enum TranscriptAssembler {
    /// Words of context compared on each side of a boundary.
    static let comparisonWindow = 15
    /// Shorter matches than this are treated as coincidence, not repetition.
    static let minimumMatchWords = 3

    static func assemble(_ chunks: [String]) -> String {
        var result = ""
        for chunk in chunks {
            let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard !result.isEmpty else {
                result = trimmed
                continue
            }
            let remainder = deduplicated(previous: result, next: trimmed)
            // A chunk can be entirely consumed by the boundary overlap (e.g.
            // previous ends "...the new build" and next is exactly "the new
            // build"). When that happens there's nothing left to append, so
            // skip both the remainder and the separator space to avoid a
            // stray double space in the transcript.
            guard !remainder.isEmpty else { continue }
            result += " " + remainder
        }
        return result
    }

    /// Drops the longest leading run of `next` (at least `minimumMatchWords`
    /// long) that repeats the trailing words of `previous`.
    static func deduplicated(previous: String, next: String) -> String {
        let previousWords = words(in: previous)
        let nextWords = words(in: next)
        guard previousWords.count >= minimumMatchWords,
              nextWords.count >= minimumMatchWords else { return next }

        let tail = Array(previousWords.suffix(comparisonWindow)).map(normalized)
        let head = Array(nextWords.prefix(comparisonWindow)).map(normalized)

        var overlap = 0
        for length in stride(from: min(tail.count, head.count), through: minimumMatchWords, by: -1) {
            if matchingWindows(Array(tail.suffix(length)), Array(head.prefix(length))) {
                overlap = length
                break
            }
        }
        guard overlap > 0 else { return next }
        return nextWords.dropFirst(overlap).joined(separator: " ")
    }

    private static func words(in text: String) -> [String] {
        text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).map(String.init)
    }

    private static func normalized(_ word: String) -> String {
        word.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Compares two equal-length windows of normalized words, treating empty
    /// normalized tokens (punctuation-only words like "-" or "...") as
    /// unmatchable. Without this, two unrelated punctuation-only tokens would
    /// both normalize to "" and compare equal, letting them falsely
    /// contribute to a boundary overlap.
    private static func matchingWindows(_ a: [String], _ b: [String]) -> Bool {
        guard a.count == b.count else { return false }
        return zip(a, b).allSatisfy { lhs, rhs in !lhs.isEmpty && lhs == rhs }
    }
}
