#if canImport(FoundationModels)
import FoundationModels
#endif

final class AICleanupService {
    private let systemPrompt = """
        You are a transcription cleanup assistant. Fix punctuation, capitalization, \
        and remove filler words (um, uh, like, you know). Do not change the meaning, \
        tone, or vocabulary. Return only the cleaned text with no commentary.
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
