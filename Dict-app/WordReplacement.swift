import Foundation

/// A user-defined fix for a word or phrase the engine keeps getting wrong
/// ("clod code" → "Claude Code"). Applied to every transcript, last, so it
/// wins over both the engine and the formatter.
struct WordReplacement: Codable, Hashable, Identifiable {
    var id = UUID()
    var spoken: String
    var replacement: String

    /// Replaces each whole-word, case-insensitive occurrence of `spoken`.
    /// Spaces inside a phrase match any run of whitespace, so a phrase still
    /// matches across a line break the formatter inserted.
    static func apply(_ replacements: [WordReplacement], to text: String) -> String {
        replacements.reduce(text) { text, rule in
            let words = rule.spoken.split(whereSeparator: \.isWhitespace)
            guard !words.isEmpty else { return text }
            let phrase = words.map { NSRegularExpression.escapedPattern(for: String($0)) }
                .joined(separator: "\\s+")
            // Lookarounds instead of \b so phrases that start or end with
            // punctuation ("node.js") still anchor on word boundaries.
            let pattern = "(?<![\\p{L}\\p{N}_])\(phrase)(?![\\p{L}\\p{N}_])"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                return text
            }
            return regex.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: NSRegularExpression.escapedTemplate(for: rule.replacement)
            )
        }
    }
}
