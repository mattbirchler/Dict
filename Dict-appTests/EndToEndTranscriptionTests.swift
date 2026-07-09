import Foundation
import Testing
import WhisperKit
@testable import Dict_app

/// Drives the exact production stop() path — gate → trim → Whisper →
/// hallucination filter — with real synthesized speech shaped like a
/// push-to-talk recording: short lead-in silence, fluent speech whose
/// volume trails off at the end, and a short release gap. Regression for
/// the bug where the final words of a dictation were trimmed away.
struct EndToEndTranscriptionTests {
    @Test func productionPipelineKeepsTrailingWords() async throws {
        let sentence = "I think we should ship the new build tomorrow "
            + "as long as we finish testing before the deadline on Friday afternoon"

        // Synthesize speech at WhisperKit's 16kHz sample rate.
        let wavURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dict-e2e-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: wavURL) }
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-o", wavURL.path, "--data-format=LEF32@16000", sentence]
        try say.run()
        say.waitUntilExit()
        #expect(say.terminationStatus == 0)

        var speech = try AudioProcessor.loadAudioAsFloatArray(fromPath: wavURL.path)
        #expect(speech.count > WhisperKit.sampleRate) // at least 1s of audio

        // Human voices drop in volume at the end of a sentence — that soft
        // tail is exactly what the old trim cut off. Attenuate the last
        // quarter of the speech to reproduce it.
        let tailStart = speech.count * 3 / 4
        for i in tailStart..<speech.count { speech[i] *= 0.35 }

        // Push-to-talk shape: brief silence after key-down, speech, then
        // key released within a second of the last word.
        let leadIn = [Float](repeating: 0, count: Int(0.2 * Float(WhisperKit.sampleRate)))
        let releaseGap = [Float](repeating: 0, count: Int(0.6 * Float(WhisperKit.sampleRate)))
        let recording = leadIn + speech + releaseGap

        // Production gate + trim.
        let gated = try #require(StreamingTranscriptionService.gateAndTrim(samples: recording))
        // Every speech sample must survive the trim (only edge silence may go).
        #expect(gated.samples.count >= speech.count)

        // Production decoding + hallucination filter.
        let modelURL = try await WhisperKit.download(variant: "distil-large-v3")
        let pipe = try await WhisperKit(WhisperKitConfig(
            modelFolder: modelURL.path, load: true, download: false
        ))
        let results = try await pipe.transcribe(
            audioArray: gated.samples,
            decodeOptions: DecodingOptions(
                language: "en",
                temperature: 0.0,
                skipSpecialTokens: true,
                wordTimestamps: false
            )
        )
        let text = TranscriptFilter().filteredText(
            segments: results.flatMap { $0.segments },
            voiceActivity: gated.voiceActivity,
            frameDuration: gated.frameDuration
        )
        print("[E2E] Transcribed: \"\(text)\"")

        // The trailing words — the ones the bug used to eat — must be there.
        #expect(text.lowercased().contains("friday afternoon"))
    }
}
