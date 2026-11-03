import Testing
@testable import Dict_app

struct FillerRemoverTests {
    @Test func dropsFillerSoundsAndKeepsEverythingElse() {
        #expect(FillerRemover.clean("um so I think uh the update is, hmm, solid") == "so I think the update is, solid")
    }

    @Test func dropsImmediateStutters() {
        #expect(FillerRemover.clean("double check the the numbers and and send it") == "double check the numbers and send it")
    }

    @Test func keepsRepeatsAcrossPunctuation() {
        // "No. No." is emphasis, not a stutter.
        #expect(FillerRemover.clean("No. No. Not that one") == "No. No. Not that one")
    }

    @Test func keepsWordsThatOnlyLookLikeFillers() {
        #expect(FillerRemover.clean("the umbrella is here") == "the umbrella is here")
        #expect(FillerRemover.clean("Uh-oh, that broke") == "Uh-oh, that broke")
    }

    @Test func neverReturnsEmptyForFillerOnlyInput() {
        #expect(FillerRemover.clean("um uh") == "um uh")
    }
}

struct DictationStyleFormatterTests {
    private func words(_ n: Int) -> String { [String](repeating: "word", count: n).joined(separator: " ") }

    @Test func cleanMayDropHalfTheWordsButNotMore() {
        #expect(TranscriptFormatter.isAcceptable(input: words(100), output: words(55), style: .clean))
        #expect(!TranscriptFormatter.isAcceptable(input: words(100), output: words(30), style: .clean))
        #expect(!TranscriptFormatter.isAcceptable(input: words(100), output: words(120), style: .clean))
    }

    @Test func polishedMayGrowALittle() {
        #expect(TranscriptFormatter.isAcceptable(input: words(100), output: words(120), style: .polished))
        #expect(!TranscriptFormatter.isAcceptable(input: words(100), output: words(140), style: .polished))
    }

    @Test func verbatimBoundsAreUnchanged() {
        #expect(!TranscriptFormatter.isAcceptable(input: words(100), output: words(85), style: .verbatim))
        #expect(TranscriptFormatter.isAcceptable(input: words(100), output: words(97), style: .verbatim))
    }

    @Test func instructionsFollowStyleAndContext() {
        #expect(TranscriptFormatter.instructions(style: .verbatim, context: .general) == TranscriptFormatter.instructions)
        #expect(TranscriptFormatter.instructions(style: .verbatim, context: .coding) == TranscriptFormatter.codingInstructions)
        let clean = TranscriptFormatter.instructions(style: .clean, context: .coding)
        #expect(clean.hasPrefix(TranscriptFormatter.cleanInstructions))
        #expect(clean.contains("coding or terminal app"))
        #expect(!TranscriptFormatter.instructions(style: .polished, context: .general).contains("coding or terminal app"))
    }

    @Test func termsAreAppendedWhenPresent() {
        let with = TranscriptFormatter.instructions(style: .clean, context: .general, terms: ["Birchtree", "Parakeet"])
        #expect(with.contains("Birchtree, Parakeet"))
        #expect(!TranscriptFormatter.instructions(style: .clean, context: .general).contains("already in the document"))
    }
}
