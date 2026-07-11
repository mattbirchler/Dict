import Foundation

@MainActor
final class PipelineCoordinator {
    let whisperEngine = StreamingTranscriptionService()
    let appleEngine = AppleSpeechTranscriptionService()
    let textInsertionService = TextInsertionService()
    let historyStore = HistoryStore()
    private let formatter = TranscriptFormatter()

    /// Mirrors the user's "Format Transcripts" setting; owned by AppState.
    var isFormattingEnabled = true

    /// Mirrors the user's transcription-engine setting; owned by AppState.
    var engineChoice: TranscriptionEngineChoice = .apple

    var activeEngine: any TranscriptionEngine {
        switch engineChoice {
        case .apple: appleEngine
        case .whisper: whisperEngine
        }
    }

    func startRecording() {
        let engine = activeEngine
        Task {
            do {
                try await engine.start()
                print("[Pipeline] Recording session started")
            } catch {
                print("[Pipeline] Failed to start: \(error)")
            }
        }
    }

    func cancelRecording() {
        activeEngine.cancel()
        print("[Pipeline] Recording cancelled")
    }

    func stopRecordingAndProcess() async -> String? {
        let rawText = await activeEngine.stop()

        guard !rawText.isEmpty else {
            print("[Pipeline] No text produced, aborting")
            return nil
        }

        let text = isFormattingEnabled ? await formatter.format(rawText) : rawText

        historyStore.save(cleanedText: text)
        print("[Pipeline] Saved to history. Inserting text...")
        await textInsertionService.insertText(text)
        print("[Pipeline] Text inserted")

        return text
    }
}
