import Foundation
import Testing
@testable import Dict_app

/// Regression for the crash where the *second* dictation after launch killed
/// the app every time.
///
/// A `SpeechTranscriber` may only ever be attached to a single
/// `SpeechAnalyzer`. The engine used to build the transcriber once in
/// `prepare()` and reuse it for every session while creating a fresh analyzer
/// each time, so session two trapped inside Speech.framework:
///
///     Speech  TranscriberCommon.worker.setter
///     Speech  SpeechAnalyzer.setWorkers(for:reusingFrom:preservingFunctionOf:)
///     Speech  SpeechAnalyzer.prepareModulesIfNeeded()
///     Speech  SpeechAnalyzer.processInput(_:)
///
/// The trap fires on the first audio buffer after start, so this test has to
/// actually run the engine briefly rather than just start and stop it.
@MainActor
struct AppleSpeechRepeatSessionTests {
    @Test func backToBackSessionsDoNotTrap() async throws {
        let engine = AppleSpeechTranscriptionService()
        try await engine.prepare()

        for session in 1...3 {
            try await engine.start()
            #expect(engine.isRecording, "session \(session) should be recording")
            // Long enough for buffers to reach SpeechAnalyzer.processInput,
            // which is where the old bug trapped.
            try await Task.sleep(for: .milliseconds(600))
            _ = await engine.stop()
            #expect(!engine.isRecording, "session \(session) should have stopped")
        }
    }
}
