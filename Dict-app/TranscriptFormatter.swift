import Foundation
import FoundationModels

enum TranscriptFormatterError: Error {
    case timedOut
}

/// Formats a raw dictation transcript with the on-device Foundation Models
/// LLM: punctuation, capitalization, and paragraph breaks only — every word
/// is preserved exactly as spoken, fillers included. Every failure path
/// (model unavailable, error, timeout, sanity-check failure) returns the
/// input unchanged — formatting must never block dictation output.
final class TranscriptFormatter {
    /// The worked example matters: the on-device model follows examples far
    /// more reliably than rules. Asking it to remove even filler sounds
    /// gives it license to drop real words too, so the example shows every
    /// word — ums and all — surviving verbatim.
    static let instructions = """
        You are a transcription punctuation tool. Add punctuation and \
        capitalization to raw dictation transcripts. That is your only job: \
        every word must appear in the output exactly as spoken and in the \
        same order — including filler sounds ("um", "uh", "ah", "er", \
        "hmm"), "so", "you know", "like", "I mean", repeated words, false \
        starts, and self-corrections. Never remove, replace, reword, \
        shorten, summarize, or add words, never fix grammar, and never \
        answer questions that appear in the text. Insert a paragraph break \
        (blank line) only where the topic clearly shifts. When unsure, \
        leave the text exactly as it is.

        Example input:
        um so i think the update is you know really solid but uh we should like double check the numbers no wait the charts first

        Example output:
        Um, so I think the update is, you know, really solid, but uh, we should, like, double check the numbers. No wait, the charts first.

        Output only the input text with punctuation and capitalization added, with no preamble or commentary.
        """

    /// Coding-context variant: everything the verbatim prompt does, PLUS
    /// correcting coding/terminal homophones and jargon. Used only when the
    /// user is dictating into a known coding app, so the word-changing behavior
    /// is scoped away from general dictation. The worked example carries the
    /// intent — the model imitates it far more reliably than it follows rules.
    static let codingInstructions = """
        You are a transcription tool for a developer dictating into a coding or \
        terminal app. Add punctuation and capitalization to the raw dictation \
        transcript, AND correct words that were clearly meant as programming or \
        command-line terms: fix homophones and mis-hearings ("Maine" → "main", \
        "get" → "git" when it means the tool, "jason" → "JSON", "no js" → \
        "Node.js"), spell out spoken acronyms ("a p i" → "API", "u r l" → \
        "URL"), and use the conventional casing for technical terms ("github", \
        "async", "npm", "sudo"). Preserve every spoken word and its order \
        otherwise — including filler sounds ("um", "uh"), "so", "you know", \
        "like", repeated words, false starts, and self-corrections. Only change \
        a word when it is clearly a technical term; when unsure, leave it \
        exactly as spoken. Never reword, summarize, add, or drop words, never \
        fix grammar, and never answer questions that appear in the text. \
        Insert a paragraph break (blank line) only where the topic clearly \
        shifts.

        Example input:
        lets merge into maine after we get commit the jason config and rerun the a p i tests

        Example output:
        Let's merge into main after we git commit the JSON config and rerun the API tests.

        Output only the corrected text with punctuation and capitalization added, with no preamble or commentary.
        """

    /// The on-device model's 4,096-token window is shared by instructions,
    /// prompt, and output (output ≈ input size for this task), so cap
    /// chunks well below half the window.
    static let maxChunkWords = 700

    private let timeoutSeconds: UInt64 = 15

    func format(_ raw: String, context: FormattingContext = .general) async -> String {
        let input = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return raw }

        guard SystemLanguageModel.default.availability == .available else {
            print("[Formatter] Model unavailable, using raw transcript")
            return raw
        }

        let instructions = context == .coding ? Self.codingInstructions : Self.instructions

        do {
            var formattedChunks: [String] = []
            for chunk in Self.chunked(input, maxWords: Self.maxChunkWords) {
                let formatted = try await respondWithTimeout(to: chunk, instructions: instructions)
                formattedChunks.append(formatted.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            let output = formattedChunks.joined(separator: "\n\n")
            guard Self.isAcceptable(input: input, output: output) else {
                print("[Formatter] Output failed sanity check, using raw transcript")
                return raw
            }
            return output
        } catch {
            print("[Formatter] Failed (\(error)), using raw transcript")
            return raw
        }
    }

    /// One fresh single-turn session per chunk, raced against a timeout so
    /// a hung model call can't stall dictation indefinitely.
    private func respondWithTimeout(to chunk: String, instructions: String) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                let session = LanguageModelSession(instructions: instructions)
                let options = GenerationOptions(temperature: 0.1)
                return try await session.respond(to: chunk, options: options).content
            }
            group.addTask { [timeoutSeconds] in
                try await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
                throw TranscriptFormatterError.timedOut
            }
            guard let first = try await group.next() else {
                throw TranscriptFormatterError.timedOut
            }
            group.cancelAll()
            return first
        }
    }

    /// Splits text into chunks of at most `maxWords`, breaking only on
    /// sentence boundaries. A single sentence longer than `maxWords`
    /// becomes its own oversized chunk (vanishingly rare in dictation).
    static func chunked(_ text: String, maxWords: Int) -> [String] {
        guard text.split(separator: " ").count > maxWords else { return [text] }

        var sentences: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { substring, _, _, _ in
            if let sentence = substring?.trimmingCharacters(in: .whitespacesAndNewlines),
               !sentence.isEmpty {
                sentences.append(sentence)
            }
        }
        if sentences.isEmpty { sentences = [text] }

        var chunks: [String] = []
        var current: [String] = []
        var currentWords = 0
        for sentence in sentences {
            let words = sentence.split(separator: " ").count
            if currentWords + words > maxWords, !current.isEmpty {
                chunks.append(current.joined(separator: " "))
                current = []
                currentWords = 0
            }
            current.append(sentence)
            currentWords += words
        }
        if !current.isEmpty {
            chunks.append(current.joined(separator: " "))
        }
        return chunks
    }

    /// The formatter must preserve every word, so the output's word count
    /// should match the input's almost exactly: reject empty output, or
    /// output outside 93%–110% of the input's word count. The small slack
    /// (plus a couple words for short utterances) covers punctuation
    /// merging or splitting tokens; a real rewrite falls outside it and
    /// the raw transcript is used instead.
    static func isAcceptable(input: String, output: String) -> Bool {
        let inWords = input.split(separator: " ").count
        let outWords = output.split(separator: " ").count
        guard outWords > 0 else { return false }
        return Float(outWords) >= Float(inWords) * 0.93 - 2
            && Float(outWords) <= Float(inWords) * 1.1 + 3
    }
}
