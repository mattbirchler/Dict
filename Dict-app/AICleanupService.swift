import FoundationModels

final class AICleanupService {
    private let systemPrompt = """
        You are a transcription cleanup assistant. Fix punctuation, capitalization, \
        and remove filler words (um, uh, like, you know). Do not change the meaning, \
        tone, or vocabulary. Return only the cleaned text with no commentary.
        """

    var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    func cleanup(rawTranscript: String) async throws -> String {
        guard isAvailable else {
            return rawTranscript
        }

        let session = LanguageModelSession(instructions: systemPrompt)
        let response = try await session.respond(to: rawTranscript)
        return response.content
    }
}
