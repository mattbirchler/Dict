import Testing
@testable import Dict_app

struct WordReplacementTests {
    private func apply(_ rules: [(String, String)], _ text: String) -> String {
        WordReplacement.apply(rules.map { WordReplacement(spoken: $0.0, replacement: $0.1) }, to: text)
    }

    @Test func replacesWholeWordsIgnoringCase() {
        #expect(apply([("dict", "Dict")], "I love DICT, and dict is great.") == "I love Dict, and Dict is great.")
    }

    @Test func doesNotReplaceInsideOtherWords() {
        #expect(apply([("dict", "Dict")], "That contradicts the dictionary.") == "That contradicts the dictionary.")
    }

    @Test func multiWordPhraseMatchesAcrossWhitespace() {
        #expect(apply([("clod code", "Claude Code")], "Open clod\ncode now.") == "Open Claude Code now.")
    }

    @Test func phrasesWithPunctuationAnchorOnWords() {
        #expect(apply([("node.js", "Node.js")], "Install node.js today.") == "Install Node.js today.")
    }

    @Test func replacementIsInsertedLiterally() {
        #expect(apply([("dollar", "$1")], "one dollar") == "one $1")
    }

    @Test func emptySpokenPhraseIsIgnored() {
        #expect(apply([("  ", "x")], "hello world") == "hello world")
    }

    @Test func rulesApplyInOrder() {
        #expect(apply([("a b", "c"), ("c", "d")], "a b") == "d")
    }
}
