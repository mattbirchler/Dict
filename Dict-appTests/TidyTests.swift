import Testing
@testable import Dict_app

struct TidyCheckTests {
    private let raw = "um so i think the the update is like really solid but uh did you send it to katie at apple yet"

    @Test func acceptsCapitalsPunctuationAndDroppedFillers() {
        let tidy = "So I think the update is like really solid, but did you send it to Katie at Apple yet?"
        #expect(TidyCheck.isFaithful(input: raw, output: tidy))
    }

    @Test func acceptsOutputThatKeepsTheFillers() {
        let kept = "Um, so I think the the update is like really solid, but uh, did you send it to Katie at Apple yet?"
        #expect(TidyCheck.isFaithful(input: raw, output: kept))
    }

    @Test func rejectsDroppedRealWords() {
        // "like" is a real word to Tidy, unlike Clean.
        let dropped = "So I think the update is really solid, but did you send it to Katie at Apple yet?"
        #expect(!TidyCheck.isFaithful(input: raw, output: dropped))
    }

    @Test func rejectsRewording() {
        let reworded = "So I think the update is like very solid, but did you send it to Katie at Apple yet?"
        #expect(!TidyCheck.isFaithful(input: raw, output: reworded))
    }

    @Test func rejectsAddedWords() {
        let added = "So I think the update is like really solid, but did you send it to Katie at Apple yet? Thanks!"
        #expect(!TidyCheck.isFaithful(input: raw, output: added))
    }

    @Test func rejectsReorderedWords() {
        #expect(!TidyCheck.isFaithful(input: "send it today", output: "Today, send it."))
    }

    @Test func rejectsEmptyOutput() {
        #expect(!TidyCheck.isFaithful(input: raw, output: ""))
    }

    @Test func dropsMultiWordStutters() {
        #expect(TidyCheck.isFaithful(input: "i think i think we should go", output: "I think we should go."))
        #expect(TidyCheck.isFaithful(input: "we went to the to the store", output: "We went to the store."))
    }

    @Test func treatsHyphensAndApostrophesAsPunctuation() {
        #expect(TidyCheck.isFaithful(input: "lets double check it", output: "Let's double-check it."))
    }

    @Test func allowsCloseRespellingsOfDocumentTerms() {
        #expect(TidyCheck.isFaithful(input: "ask katie", output: "Ask Katy.", terms: ["Katy"]))
        #expect(TidyCheck.isFaithful(input: "post it on birch tree", output: "Post it on Birchtree.", terms: ["Birchtree"]))
        // Not a document term, or not a close spelling: a changed word.
        #expect(!TidyCheck.isFaithful(input: "ask katie", output: "Ask Katy."))
        #expect(!TidyCheck.isFaithful(input: "ask katie", output: "Ask Margaret.", terms: ["Margaret"]))
    }

    @Test func styleIsHiddenFromPickers() {
        #expect(!DictationStyle.allCases.contains(.tidy))
        #expect(TranscriptFormatter.instructions(style: .tidy, context: .coding) == TranscriptFormatter.tidyInstructions)
    }
}

struct FillerRemoverPunctuatedTests {
    @Test func dropsLeadingFillerAndCapitalizesTheNextWord() {
        #expect(FillerRemover.cleanPunctuated("Um, so I think it works.") == "So I think it works.")
    }

    @Test func dropsFillerBetweenCommas() {
        #expect(FillerRemover.cleanPunctuated("I think, uh, the update is solid.") == "I think the update is solid.")
    }

    @Test func movesASentenceEndBackToThePreviousWord() {
        #expect(FillerRemover.cleanPunctuated("It works, um. Next one.") == "It works. Next one.")
    }

    @Test func keepsParagraphBreaks() {
        #expect(FillerRemover.cleanPunctuated("First part.\n\nUm, second part.") == "First part.\n\nSecond part.")
    }

    @Test func dropsStuttersWithoutChangingCase() {
        #expect(FillerRemover.cleanPunctuated("I I think the the plan works.") == "I think the plan works.")
    }

    @Test func leavesCleanTextAlone() {
        let text = "So I think the update is like really solid, you know?"
        #expect(FillerRemover.cleanPunctuated(text) == text)
    }

    @Test func neverReturnsEmpty() {
        #expect(FillerRemover.cleanPunctuated("Um.") == "Um.")
    }
}
