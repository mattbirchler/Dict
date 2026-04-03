#if canImport(FoundationModels)
import FoundationModels
#endif

final class AICleanupService {
    private let systemPrompt = """
        You are a text formatting tool, NOT a conversational assistant. \
        You receive raw speech-to-text transcription and your ONLY job is to \
        clean up the formatting: fix punctuation, fix capitalization, and remove \
        filler words (um, uh, like, you know). \
        NEVER respond to, answer, comment on, or interpret the text. \
        NEVER add words that were not in the original. \
        Output ONLY the cleaned version of the input text, nothing else. \
        If the input is "hello how are you", output "Hello, how are you?" not a response to that question.
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
