import Foundation
import FoundationModels

enum TranscriptFormatterError: Error {
    case timedOut
}

/// Formats a raw dictation transcript with the on-device Foundation Models
/// LLM: punctuation, capitalization, paragraph breaks, filler-word removal,
/// and stitched self-corrections. Every failure path (model unavailable,
/// error, timeout, sanity-check failure) returns the input unchanged —
/// formatting must never block dictation output.
final class TranscriptFormatter {
    /// The worked example matters: the on-device model follows examples far
    /// more reliably than rules, and without one it drops casual phrasing
    /// ("you know", "so", "I mean") along with the fillers.
    static let instructions = """
        You are a transcription cleanup tool. Add punctuation and \
        capitalization to raw dictation transcripts, and remove filler sounds \
        ("um", "uh", "ah", "er", "hmm"). Make no other changes: every \
        remaining word must appear exactly as spoken and in the same order — \
        including "so", "you know", "like", "I mean", repeated words, and \
        self-corrections. Insert a paragraph break (blank line) only where \
        the topic clearly shifts. Never reword, summarize, or add content, \
        and never answer questions that appear in the text.

        Example input:
        um so i think the update is you know really solid but uh we should like double check the numbers no wait the charts first

        Example output:
        So I think the update is, you know, really solid, but we should, like, double check the numbers. No wait, the charts first.

        Output only the cleaned-up text with no preamble or commentary.
        """

    /// The on-device model's 4,096-token window is shared by instructions,
    /// prompt, and output (output ≈ input size for this task), so cap
    /// chunks well below half the window.
    static let maxChunkWords = 700

    private let timeoutSeconds: UInt64 = 15

    func format(_ raw: String) async -> String {
        let input = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return raw }

        guard SystemLanguageModel.default.availability == .available else {
            print("[Formatter] Model unavailable, using raw transcript")
            return raw
        }

        do {
            var formattedChunks: [String] = []
            for chunk in Self.chunked(input, maxWords: Self.maxChunkWords) {
                let formatted = try await respondWithTimeout(to: chunk)
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
    private func respondWithTimeout(to chunk: String) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                let session = LanguageModelSession(instructions: Self.instructions)
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

    /// The formatter may remove filler sounds but must not eat or invent
    /// content: reject empty output, or output outside 85%–125% of the
    /// input's word count (with a few words of slack so short utterances
    /// can shed proportionally more fillers).
    static func isAcceptable(input: String, output: String) -> Bool {
        let inWords = input.split(separator: " ").count
        let outWords = output.split(separator: " ").count
        guard outWords > 0 else { return false }
        return Float(outWords) >= Float(inWords) * 0.85 - 3
            && Float(outWords) <= Float(inWords) * 1.25 + 10
    }
}
