import AppKit
import Foundation

/// Respells words in a transcript to match terms already in the document
/// (see ScreenContext.extractTerms), without a language model:
///
/// - Same letters, different case: "birchtree" becomes "Birchtree" and
///   "iphone" becomes "iPhone". For plain Capitalized terms and all-caps
///   acronyms, skipped when the spoken word is an ordinary dictionary word,
///   so a document that mentions "Mark" or "US" doesn't change every "mark"
///   or "us". Mixed-case terms (iPhone, MacBook, GitHub) always apply: the
///   system spell checker accepts their lowercase forms, and they're too
///   distinctive to collide with ordinary words.
/// - The term split into words: "birch tree" or "Birch-Tree" becomes
///   "Birchtree". Only for terms made of letters and digits, at least
///   four characters long, split at most twice.
nonisolated enum ScreenContextSpelling {
    static let minimumJoinedLength = 4
    static let maximumSplits = 2

    /// Returns `text` with matching words respelled, and how many changed.
    static func apply(
        terms: [String],
        to text: String,
        isDictionaryWord: (String) -> Bool
    ) -> (text: String, fixes: Int) {
        var result = text
        var fixes = 0
        // Longest first, so "MacBookPro" gets its chance before "MacBook".
        for term in terms.sorted(by: { $0.count > $1.count }) {
            guard let regex = regex(for: term) else { continue }
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            // Back to front, so earlier ranges stay valid as text changes.
            for match in matches.reversed() {
                guard let range = Range(match.range, in: result) else { continue }
                let spoken = String(result[range])
                guard spoken != term else { continue }
                let splits = spoken.filter { $0 == " " || $0 == "-" }.count
                if splits == 0 {
                    if !isMixedCase(term), isDictionaryWord(spoken.lowercased()) { continue }
                } else if splits > maximumSplits {
                    continue
                }
                result.replaceSubrange(range, with: term)
                fixes += 1
            }
        }
        return (result, fixes)
    }

    /// A capital after the first character plus at least one lowercase
    /// letter: "iPhone", "MacBook". Not "Mark" or "URL".
    static func isMixedCase(_ term: String) -> Bool {
        term.dropFirst().contains { $0.isUppercase } && term.contains { $0.isLowercase }
    }

    /// Whole-word, case-insensitive. Letters-and-digits terms may also be
    /// split by single spaces or hyphens between any two characters.
    static func regex(for term: String) -> NSRegularExpression? {
        let characters = term.map { NSRegularExpression.escapedPattern(for: String($0)) }
        let joinable = term.count >= minimumJoinedLength && term.allSatisfy { $0.isLetter || $0.isNumber }
        let body = characters.joined(separator: joinable ? "[ -]?" : "")
        let pattern = "(?<![\\p{L}\\p{N}_])\(body)(?![\\p{L}\\p{N}_])"
        return try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
    }

    /// Whether the system spell checker knows `word`, in the user's language.
    @MainActor
    static func systemDictionaryContains(_ word: String) -> Bool {
        let misspelled = NSSpellChecker.shared.checkSpelling(of: word, startingAt: 0)
        return misspelled.location == NSNotFound
    }
}
