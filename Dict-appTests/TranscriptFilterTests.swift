import Testing
import WhisperKit
@testable import Dict_app

struct TranscriptFilterTests {
    let filter = TranscriptFilter()

    private func segment(
        _ text: String,
        start: Float = 0,
        end: Float = 2,
        noSpeechProb: Float = 0.1
    ) -> TranscriptionSegment {
        TranscriptionSegment(start: start, end: end, text: text, noSpeechProb: noSpeechProb)
    }

    // 20 frames at 0.1s = 2 seconds of audio
    private let allVoiced = [Bool](repeating: true, count: 20)
    private let allSilent = [Bool](repeating: false, count: 20)

    @Test func keepsNormalSpeech() {
        let text = filter.filteredText(
            segments: [segment(" Hello world.")],
            voiceActivity: allVoiced,
            frameDuration: 0.1
        )
        #expect(text == "Hello world.")
    }

    @Test func dropsHighNoSpeechProbEvenOverVoicedAudio() {
        let text = filter.filteredText(
            segments: [segment("Anything at all.", noSpeechProb: 0.8)],
            voiceActivity: allVoiced,
            frameDuration: 0.1
        )
        #expect(text.isEmpty)
    }

    @Test func dropsBlocklistPhraseOverSilence() {
        let text = filter.filteredText(
            segments: [segment(" Thank you.")],
            voiceActivity: allSilent,
            frameDuration: 0.1
        )
        #expect(text.isEmpty)
    }

    @Test func keepsBlocklistPhraseOverRealSpeech() {
        let text = filter.filteredText(
            segments: [segment(" Thank you.")],
            voiceActivity: allVoiced,
            frameDuration: 0.1
        )
        #expect(text == "Thank you.")
    }

    @Test func keepsNonBlocklistTextOverSilentVAD() {
        // Quiet-but-real speech the VAD missed must not be eaten
        // unless it is a known hallucination phrase.
        let text = filter.filteredText(
            segments: [segment("The meeting is at noon.")],
            voiceActivity: allSilent,
            frameDuration: 0.1
        )
        #expect(text == "The meeting is at noon.")
    }

    @Test func normalizationStripsPunctuationAndCase() {
        #expect(TranscriptFilter.normalize(" Thank You!!! ") == "thank you")
        #expect(TranscriptFilter.normalize("Thanks for watching.") == "thanks for watching")
    }

    @Test func joinsKeptSegmentsWithSingleSpaces() {
        let text = filter.filteredText(
            segments: [
                segment(" First part.", start: 0, end: 1),
                segment(" Second part.", start: 1, end: 2),
            ],
            voiceActivity: allVoiced,
            frameDuration: 0.1
        )
        #expect(text == "First part. Second part.")
    }

    @Test func blocklistChecksOnlyTheSegmentsOwnTimeWindow() {
        // Speech in frames 0..<10, silence in 10..<20. A "Thank you."
        // hallucinated during the silent tail must be dropped even though
        // the recording contains speech elsewhere.
        let halfVoiced = [Bool](repeating: true, count: 10) + [Bool](repeating: false, count: 10)
        let text = filter.filteredText(
            segments: [
                segment(" Hello there.", start: 0, end: 1),
                segment(" Thank you.", start: 1, end: 2),
            ],
            voiceActivity: halfVoiced,
            frameDuration: 0.1
        )
        #expect(text == "Hello there.")
    }
}
