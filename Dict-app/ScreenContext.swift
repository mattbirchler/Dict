import AppKit
import Foundation

/// Names and terms already present in the field the user is dictating
/// into, read through Accessibility so the formatter spells them the way
/// the document does. Everything stays in memory for one request.
enum ScreenContext {
    /// Characters of the focused field read at most; plenty for terms.
    static let maxCharacters = 20_000
    static let maxTerms = 40

    /// Words that are capitalized for grammar, not because they are names.
    static let stopWords: Set<String> = [
        "i", "i'm", "i've", "i'll", "i'd", "the", "a", "an", "and", "but", "or", "so", "if", "it", "it's", "this", "that",
        "these", "those", "we", "we're", "you", "he", "she", "they", "my", "our", "your", "his", "her", "their", "in", "on",
        "at", "to", "for", "of", "with", "from", "by", "as", "is", "are", "was", "were", "be", "been", "do", "does", "did",
        "not", "no", "yes", "ok", "okay", "hi", "hello", "hey", "thanks", "thank", "please", "when", "what", "why", "how",
        "who", "where", "which", "there", "here", "then", "than", "also", "just", "very", "can", "could", "would", "should",
        "will", "may", "might", "have", "has", "had", "let", "let's", "one", "two", "all", "any", "some", "more", "most",
        "new", "now", "today", "tomorrow", "yesterday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
    ]

    /// The text of the focused field, or nil when the app doesn't expose it.
    static func focusedText() -> String? {
        guard let focused = FocusedElement.current(timeout: 0.25) else { return nil }
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused, kAXValueAttribute as CFString, &valueRef) == .success,
              let text = valueRef as? String, !text.isEmpty else { return nil }
        return String(text.suffix(maxCharacters))
    }

    /// Terms worth telling the formatter about, most frequent first:
    /// capitalized words that aren't just starting a sentence, acronyms,
    /// CamelCase and snake_case identifiers, words with digits, and
    /// file-like tokens such as `main.swift`.
    static func extractTerms(from text: String, limit: Int = maxTerms) -> [String] {
        var counts: [String: Int] = [:]
        var order: [String] = []
        // Capitalized sentence-starters seen so far; a second appearance
        // anywhere makes them a name.
        var starters: [String: Int] = [:]
        var previousEndedSentence = true
        for rawToken in text.split(whereSeparator: { $0.isWhitespace }) {
            let token = String(rawToken).trimmingCharacters(in: Self.edgePunctuation)
            defer { previousEndedSentence = rawToken.last.map { ".!?:\n".contains($0) } ?? previousEndedSentence }
            guard token.count >= 2, token.count <= 40 else { continue }
            guard let first = token.first else { continue }
            let lower = token.lowercased()
            if stopWords.contains(lower) { continue }
            let hasDigit = token.contains { $0.isNumber }
            let hasInnerCapital = token.dropFirst().contains { $0.isUppercase }
            let hasIdentifierShape = token.contains("_") || (token.contains(".") && !token.hasSuffix("."))
            let isAcronym = token.count >= 2 && token.allSatisfy { $0.isUppercase || $0.isNumber }
            let isCapitalizedMidSentence = first.isUppercase && !previousEndedSentence
            let isCapitalizedRepeat = first.isUppercase && previousEndedSentence && (starters[token] != nil || counts[token] != nil)
            guard hasDigit || hasInnerCapital || hasIdentifierShape || isAcronym || isCapitalizedMidSentence || isCapitalizedRepeat else {
                if first.isUppercase && previousEndedSentence && token.allSatisfy({ $0.isLetter || $0 == "'" }) {
                    starters[token, default: 0] += 1
                }
                continue
            }
            if counts[token] == nil {
                order.append(token)
                // Earlier sentence-start appearances count once it's a name.
                counts[token] = starters.removeValue(forKey: token) ?? 0
            }
            counts[token, default: 0] += 1
        }
        return order
            .sorted {
                let (a, b) = (counts[$0]!, counts[$1]!)
                return a != b ? a > b : order.firstIndex(of: $0)! < order.firstIndex(of: $1)!
            }
            .prefix(limit)
            .map { $0 }
    }

    /// Trimmed from both ends only, so `main.swift` and `user_id` keep their insides.
    private static let edgePunctuation = CharacterSet.punctuationCharacters
        .union(.symbols)
        .subtracting(CharacterSet(charactersIn: "_"))
}
