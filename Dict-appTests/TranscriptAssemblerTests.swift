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
            "the deadline is Friday.",
            "Friday, and we cannot move it"
        ])
        #expect(out == "the deadline is Friday. and we cannot move it")
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
}
