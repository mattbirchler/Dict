import Foundation
import Testing
import WhisperKit
@testable import Dict_app

/// Drives the production Parakeet decode path with real synthesized speech
/// shaped like a push-to-talk recording. This is the ship gate for the
/// FluidAudio integration: it downloads the real model (cached after the
/// first run) and proves the engine turns speech into the right words.
struct ParakeetEndToEndTests {
    @Test func productionDecodeTranscribesSpeech() async throws {
        let sentence = "I think we should ship the new build tomorrow "
            + "as long as we finish testing before the deadline on Friday afternoon"

        // Synthesize speech at Parakeet's 16kHz sample rate.
        let wavURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dict-parakeet-e2e-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: wavURL) }
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-o", wavURL.path, "--data-format=LEF32@16000", sentence]
        try say.run()
        say.waitUntilExit()
        #expect(say.terminationStatus == 0)

        let speech = try AudioProcessor.loadAudioAsFloatArray(fromPath: wavURL.path)
        #expect(speech.count > 16_000) // at least 1s of audio

        // Push-to-talk shape: brief silence after key-down, speech, then
        // key released within a second of the last word.
        let leadIn = [Float](repeating: 0, count: Int(0.2 * 16_000))
        let releaseGap = [Float](repeating: 0, count: Int(0.6 * 16_000))
        let recording = leadIn + speech + releaseGap

        let service = ParakeetTranscriptionService()
        try await service.prepare()
        let text = await service.transcribeRecording(recording)

        // Semantic equivalence, not verbatim: synthesized audio plus ASR
        // can wobble on small words, but the key phrases must survive.
        let normalized = TranscriptFilter.normalize(text)
        #expect(normalized.contains("ship the new build"))
        #expect(normalized.contains("before the deadline"))
        #expect(normalized.contains("friday afternoon"))
    }
}
