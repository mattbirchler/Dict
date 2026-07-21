import Foundation
import Testing
@testable import Dict_app

struct TranscriptAssemblerTests {
    @Test func joinsChunksWithSingleSpace() {
        let out = TranscriptAssembler.assemble(["hello there", "how are you"])
        #expect(out == "hello there how are you")
    }

    @Test func skipsEmptyChunks() {
        let out = TranscriptAssembler.assemble(["hello", "", "world"])
        #expect(out == "hello world")
    }

    @Test func removesRepeatedBoundaryPhrase() {
        // The prompt made Whisper re-emit the previous chunk's tail.
        let out = TranscriptAssembler.assemble([
            "we should ship the new build tomorrow",
            "ship the new build tomorrow as long as testing passes"
        ])
        #expect(out == "we should ship the new build tomorrow as long as testing passes")
    }

    @Test func ignoresCaseAndPunctuationWhenMatching() {
        let out = TranscriptAssembler.assemble([
            "we agreed the deadline is Friday.",
            "The Deadline Is Friday, and we cannot move it"
        ])
        #expect(out == "we agreed the deadline is Friday. and we cannot move it")
    }

    @Test func doesNotStripShortIncidentalOverlap() {
        // Two words is below the 3-word minimum: a real repetition of common
        // words must not be swallowed.
        let out = TranscriptAssembler.assemble(["we need to", "to go now"])
        #expect(out == "we need to to go now")
    }

    @Test func handlesSingleChunk() {
        #expect(TranscriptAssembler.assemble(["just one"]) == "just one")
    }

    @Test func handlesNoChunks() {
        #expect(TranscriptAssembler.assemble([]) == "")
    }

    @Test func fullyConsumedChunkLeavesNoDoubleSpace() {
        // The middle chunk is entirely swallowed as a boundary repeat of the
        // previous chunk's tail, and the chunk after it must still join
        // cleanly with a single space, not a stray double space.
        let out = TranscriptAssembler.assemble([
            "we should ship the new build",
            "the new build",
            "as long as tests pass"
        ])
        #expect(out == "we should ship the new build as long as tests pass")
        #expect(!out.contains("  "))
    }

    @Test func assemblesThreeOrMoreChunksInSequence() {
        let out = TranscriptAssembler.assemble([
            "the meeting starts at nine am",
            "at nine am we will review budget",
            "we will review budget then adjourn"
        ])
        #expect(out == "the meeting starts at nine am we will review budget then adjourn")
    }

    @Test func skipsWhitespaceOnlyChunk() {
        let out = TranscriptAssembler.assemble(["hello there", "   ", "world class"])
        #expect(out == "hello there world class")
        #expect(!out.contains("  "))
    }

    @Test func punctuationOnlyTokensDoNotCountAsOverlap() {
        // "..." and "---" both normalize to the empty string (normalized()
        // strips everything but letters/numbers), so without the
        // `!lhs.isEmpty` guard in `matchingWindows` these two unrelated
        // punctuation-only tokens would compare equal purely because both
        // normalize to "", letting a 3-word run of punctuation falsely
        // count as a repeated boundary phrase and get stripped from `next`.
        // With the guard, punctuation-only tokens can never match, so no
        // overlap is found here and nothing should be stripped.
        let previous = "the meeting ended well ... ... ..."
        let next = "--- --- --- we start the recap"
        let out = TranscriptAssembler.assemble([previous, next])
        #expect(out == previous + " " + next)
    }

    @Test func overlapLongerThanComparisonWindowIsNotFullyDetected() {
        // The real repeated run here is 20 words, longer than
        // `comparisonWindow` (15). Because both sides of the comparison are
        // truncated to the window, the shifted 20-word run never lines up
        // within the 15-word slices that get compared, so no overlap is
        // found. The behavior is still sane: no crash, no partial/garbled
        // words, just an un-deduplicated (fully duplicated) join.
        let previous = "alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima mike november oscar papa quebec romeo sierra tango uniform victor whiskey xray yankee"
        let next = "foxtrot golf hotel india juliet kilo lima mike november oscar papa quebec romeo sierra tango uniform victor whiskey xray yankee"
        let out = TranscriptAssembler.assemble([previous, next])
        #expect(out == previous + " " + next)
    }
}
