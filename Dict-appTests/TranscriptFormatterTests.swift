import Testing
@testable import Dict_app

struct TranscriptFormatterTests {
    // MARK: chunked

    @Test func shortTextIsASingleChunk() {
        let text = "Hello world. This is short."
        #expect(TranscriptFormatter.chunked(text, maxWords: 700) == [text])
    }

    @Test func longTextSplitsOnSentenceBoundariesUnderMaxWords() {
        // 100 sentences x 10 words = 1000 words
        let sentence = "One two three four five six seven eight nine ten."
        let text = [String](repeating: sentence, count: 100).joined(separator: " ")
        let chunks = TranscriptFormatter.chunked(text, maxWords: 700)

        #expect(chunks.count == 2)
        for chunk in chunks {
            #expect(chunk.split(separator: " ").count <= 700)
            // Sentence boundaries respected: every chunk ends with a period.
            #expect(chunk.hasSuffix("."))
        }
        // No words lost.
        let totalWords = chunks.map { $0.split(separator: " ").count }.reduce(0, +)
        #expect(totalWords == 1000)
    }

    // MARK: isAcceptable

    @Test func acceptsOutputWithNearIdenticalWordCount() {
        let input = [String](repeating: "word", count: 100).joined(separator: " ")
        let output = [String](repeating: "word", count: 97).joined(separator: " ")
        #expect(TranscriptFormatter.isAcceptable(input: input, output: output))
    }

    @Test func rejectsEmptyOutput() {
        #expect(!TranscriptFormatter.isAcceptable(input: "some real words here", output: ""))
    }

    @Test func rejectsOutputThatAteContent() {
        let input = [String](repeating: "word", count: 100).joined(separator: " ")
        let output = [String](repeating: "word", count: 50).joined(separator: " ")
        #expect(!TranscriptFormatter.isAcceptable(input: input, output: output))
    }

    @Test func rejectsFillerLevelWordLoss() {
        // No words may be removed anymore — not even fillers — so losing
        // 15% of a 100-word transcript means the model rewrote it.
        let input = [String](repeating: "word", count: 100).joined(separator: " ")
        let output = [String](repeating: "word", count: 85).joined(separator: " ")
        #expect(!TranscriptFormatter.isAcceptable(input: input, output: output))
    }

    @Test func allowsACoupleWordsOfSlackOnShortInputs() {
        // Punctuation can merge or split a token or two; on a 12-word
        // utterance that's proportionally large but still fine.
        let input = [String](repeating: "word", count: 12).joined(separator: " ")
        let output = [String](repeating: "word", count: 10).joined(separator: " ")
        #expect(TranscriptFormatter.isAcceptable(input: input, output: output))
    }

    @Test func rejectsOutputThatAddedContent() {
        let input = [String](repeating: "word", count: 100).joined(separator: " ")
        let output = [String](repeating: "word", count: 120).joined(separator: " ")
        #expect(!TranscriptFormatter.isAcceptable(input: input, output: output))
    }

    // MARK: format fallback

    @Test func formatReturnsInputWhenInputIsBlank() async {
        let formatter = TranscriptFormatter()
        let result = await formatter.format("   ")
        #expect(result == "   ")
    }
}
