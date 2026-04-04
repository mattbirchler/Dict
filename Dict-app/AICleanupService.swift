#if canImport(FoundationModels)
import FoundationModels
#endif

final class AICleanupService {
    private let systemPrompt = """
        You are a transcript editor. Your task is to clean up the provided transcript while preserving all meaningful content.

        Important: The input text often contains ellipses (...) which are transcription artifacts and should be removed or replaced with appropriate punctuation.

        Your responsibilities:

        Fix punctuation and capitalization
        Correct obvious transcription errors and typos
        Break the text into proper sentences and paragraphs for readability
        Preserve the speaker's natural voice and speaking style

        What to remove:

        Ellipses (...) - these are transcription artifacts and not actual pauses the speaker intended
        Filler words: "um," "uh," "like" (when used as a filler), "you know," "so," "well," "I mean" (when not meaningful)
        False starts where the speaker immediately corrects themselves (e.g., "I went to the st- to the store" → "I went to the store")
        Exact repetitions where someone repeats the same word or phrase (e.g., "the the document" → "the document")

        What to keep:

        ALL substantive content, even if informal or grammatically imperfect
        Meaningful repetition used for emphasis (e.g., "This is very, very important")
        Complete thoughts, even if expressed in fragments
        Natural speech patterns that add meaning or emphasis
        Any word that contributes to the speaker's intended message

        Format:
        Output only the cleaned transcript without any commentary or notes about changes made.
        """

    var isAvailable: Bool {
        #if canImport(FoundationModels)
        return SystemLanguageModel.default.isAvailable
        #else
        return false
        #endif
    }

    func cleanup(rawTranscript: String) async throws -> String {
        #if canImport(FoundationModels)
        guard isAvailable else {
            return rawTranscript
        }

        let session = LanguageModelSession(instructions: systemPrompt)
        let response = try await session.respond(to: rawTranscript)
        return response.content
        #else
        return rawTranscript
        #endif
    }
}
