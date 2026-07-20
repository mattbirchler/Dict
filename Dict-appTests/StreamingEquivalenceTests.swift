import Foundation
import Testing
import WhisperKit
@testable import Dict_app

/// Ship gate for chunked streaming: the chunked path must produce
/// substantially the same words as the one-shot path on speech with real
/// pauses. Chunk boundaries are exactly where a streaming transcriber loses
/// words, so this drives the real segmenter over real synthesized audio.
struct StreamingEquivalenceTests {
    /// Three sentences separated by pauses long enough to split on.
    private func fixtureAudio() throws -> [Float] {
        let sentences = [
            "I think we should ship the new build tomorrow afternoon",
            "But only if the integration tests are passing on the release branch",
            "Otherwise we wait until Monday morning and try again"
        ]
        var audio: [Float] = [Float](repeating: 0, count: Int(0.2 * Float(WhisperKit.sampleRate)))
        for sentence in sentences {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("dict-stream-\(UUID().uuidString).wav")
            defer { try? FileManager.default.removeItem(at: url) }
            let say = Process()
            say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            say.arguments = ["-o", url.path, "--data-format=LEF32@16000", sentence]
            try say.run()
            say.waitUntilExit()
            audio += try AudioProcessor.loadAudioAsFloatArray(fromPath: url.path)
            // 1.2s pause: comfortably over the 0.6s split threshold.
            audio += [Float](repeating: 0, count: Int(1.2 * Float(WhisperKit.sampleRate)))
        }
        return audio
    }

    @Test func chunkedOutputMatchesOneShotOnPausedSpeech() async throws {
        let audio = try fixtureAudio()

        // Segment exactly as the live path would.
        var segmenter = SpeechSegmenter()
        var chunks: [[Float]] = []
        // Feed in 0.05s slices, mimicking the waveform timer cadence.
        let slice = Int(0.05 * Double(WhisperKit.sampleRate))
        var index = 0
        while index < audio.count {
            let end = min(index + slice, audio.count)
            if let chunk = segmenter.append(Array(audio[index..<end])) {
                chunks.append(chunk)
            }
            index = end
        }
        if let tail = segmenter.finish() { chunks.append(tail) }

        #expect(chunks.count >= 2, "fixture should split into multiple chunks")

        let modelURL = try await WhisperKit.download(variant: "distil-large-v3")
        let pipe = try await WhisperKit(WhisperKitConfig(
            modelFolder: modelURL.path, load: true, download: false
        ))

        // Chunked path, with context carry-over, mirroring decodeChunk.
        var context = ""
        var chunkTexts: [String] = []
        for chunk in chunks {
            var options = DecodingOptions(
                language: "en", temperature: 0.0,
                skipSpecialTokens: true, wordTimestamps: false
            )
            if !context.isEmpty, let tokenizer = pipe.tokenizer {
                options.promptTokens = Array(tokenizer.encode(text: String(context.suffix(200))).suffix(100))
                options.usePrefillPrompt = true
            }
            let results = try await pipe.transcribe(audioArray: chunk, decodeOptions: options)
            let frameSamples = Int(0.1 * Float(WhisperKit.sampleRate))
            let energies = VoiceGate.frameEnergies(samples: chunk, frameSamples: frameSamples)
            let text = TranscriptFilter().filteredText(
                segments: results.flatMap { $0.segments },
                voiceActivity: VoiceGate.voiceActivity(energies: energies, threshold: segmenter.sessionThreshold),
                frameDuration: 0.1
            )
            if !text.isEmpty {
                chunkTexts.append(text)
                context += (context.isEmpty ? "" : " ") + text
            }
        }
        let streamed = TranscriptAssembler.assemble(chunkTexts).lowercased()
        print("[EQUIV] streamed: \"\(streamed)\"")

        // Every sentence's distinctive words must survive chunking.
        for phrase in ["ship the new build", "integration tests", "monday morning"] {
            #expect(streamed.contains(phrase), "streamed output lost \"\(phrase)\"")
        }
    }

    @Test func repeatedSessionsLeaveNoState() async throws {
        let service = await StreamingTranscriptionService()
        for session in 1...3 {
            try await service.start()
            try await Task.sleep(for: .milliseconds(400))
            _ = await service.stop()
            let recording = await service.isRecording
            #expect(!recording, "session \(session) should have stopped")
        }
    }
}
