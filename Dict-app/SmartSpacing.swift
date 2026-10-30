import Foundation

/// Decides whether a dictation needs a separating space in front of it, from
/// the character just before the cursor. Pure so it's testable without a
/// focused text field.
enum SmartSpacing {
    /// Characters after which new text attaches directly: opening brackets
    /// and quotes, and path/handle prefixes.
    private static let attachingCharacters: Set<Character> = [
        "(", "[", "{", "<", "\"", "'", "\u{201C}", "\u{2018}", "/", "@", "#", "-", "\u{2014}",
    ]

    /// Characters that attach to whatever comes before them, so a dictation
    /// starting with one never gets a leading space.
    private static let closingCharacters: Set<Character> = [
        ".", ",", ";", ":", "!", "?", ")", "]", "}", "\u{201D}", "\u{2019}", "%",
    ]

    /// - Parameter preceding: the character before the cursor, or nil when
    ///   the cursor is at the start of the field or the app doesn't expose it.
    static func needsLeadingSpace(preceding: Character?, text: String) -> Bool {
        guard let preceding, let first = text.first else { return false }
        if preceding.isWhitespace || attachingCharacters.contains(preceding) { return false }
        if first.isWhitespace || closingCharacters.contains(first) { return false }
        return true
    }
}
