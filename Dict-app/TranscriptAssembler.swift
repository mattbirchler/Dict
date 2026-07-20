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
            result += " " + deduplicated(previous: result, next: trimmed)
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
            if Array(tail.suffix(length)) == Array(head.prefix(length)) {
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
}
