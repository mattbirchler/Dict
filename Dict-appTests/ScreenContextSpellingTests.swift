import Foundation
import Testing
@testable import Dict_app

struct ScreenContextSpellingTests {
    /// Stand-in for the system spell checker.
    private let dictionary: Set<String> = ["mark", "us", "apple", "note", "book", "the", "birch", "tree"]

    private func apply(_ terms: [String], to text: String) -> (text: String, fixes: Int) {
        ScreenContextSpelling.apply(terms: terms, to: text, isDictionaryWord: { dictionary.contains($0) })
    }

    @Test func fixesCaseOfNonDictionaryWords() {
        let result = apply(["Birchtree", "URL", "GitHub"], to: "I posted the url to birchtree and github.")
        #expect(result.text == "I posted the URL to Birchtree and GitHub.")
        #expect(result.fixes == 3)
    }

    /// A document that mentions Mark or the US shouldn't touch ordinary words.
    @Test func leavesDictionaryWordsAlone() {
        let result = apply(["Mark", "US", "Apple"], to: "Let us mark the apple.")
        #expect(result.text == "Let us mark the apple.")
        #expect(result.fixes == 0)
    }

    /// The system spell checker accepts "iphone" and "macbook", but
    /// mixed-case terms are distinctive enough to fix anyway.
    @Test func mixedCaseTermsIgnoreTheDictionary() {
        let result = ScreenContextSpelling.apply(
            terms: ["iPhone", "FluidAudio"],
            to: "My iphone runs fluidaudio.",
            isDictionaryWord: { _ in true }
        )
        #expect(result.text == "My iPhone runs FluidAudio.")
        #expect(ScreenContextSpelling.isMixedCase("MacBook"))
        #expect(!ScreenContextSpelling.isMixedCase("Mark"))
        #expect(!ScreenContextSpelling.isMixedCase("URL"))
    }

    /// Split spellings join back up, even when each piece is a real word.
    @Test func joinsSplitTerms() {
        #expect(apply(["Birchtree"], to: "Check birch tree today.").text == "Check Birchtree today.")
        #expect(apply(["Birchtree"], to: "Check Birch-Tree today.").text == "Check Birchtree today.")
        #expect(apply(["MacBook"], to: "My mac book died.").text == "My MacBook died.")
    }

    @Test func matchesWholeWordsOnly() {
        #expect(apply(["Dict"], to: "The dictionary is dict.").text == "The dictionary is Dict.")
        #expect(apply(["Birchtree"], to: "birchtrees").text == "birchtrees")
    }

    @Test func keepsPossessivesAndPunctuation() {
        #expect(apply(["Birchtree"], to: "birchtree's post, birchtree.").text == "Birchtree's post, Birchtree.")
    }

    /// Identifiers only change case; they don't absorb neighboring words.
    @Test func identifiersAreCaseOnly() {
        #expect(apply(["user_id"], to: "Set USER_ID now.").text == "Set user_id now.")
        #expect(apply(["main.swift"], to: "Open Main.swift.").text == "Open main.swift.")
        #expect(apply(["user_id"], to: "the user id").text == "the user id")
    }

    @Test func shortTermsDontJoin() {
        #expect(apply(["Kia"], to: "ki a").text == "ki a")
    }

    @Test func tooManySplitsAreLeftAlone() {
        #expect(apply(["Birchtree"], to: "bi rch tr ee").text == "bi rch tr ee")
    }

    @Test func alreadyCorrectIsNotAFix() {
        let result = apply(["Birchtree"], to: "Birchtree is fine.")
        #expect(result.text == "Birchtree is fine.")
        #expect(result.fixes == 0)
    }

    @Test func noTermsNoChange() {
        #expect(apply([], to: "hello there").text == "hello there")
    }
}
