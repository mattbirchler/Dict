import AppKit
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

    /// Mirrors the user's "space after each dictation" setting; owned by AppState.
    var appendTrailingSpace = false

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

        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let context: FormattingContext = CodingAppCatalog.isCodingApp(bundleID) ? .coding : .general
        let text = isFormattingEnabled ? await formatter.format(rawText, context: context) : rawText

        historyStore.save(cleanedText: text)
        print("[Pipeline] Saved to history. Inserting text...")
        // Append the separator space to the inserted text only — History keeps
        // the clean text so the list stays tidy.
        let textToInsert = appendTrailingSpace ? text + " " : text
        await textInsertionService.insertText(textToInsert)
        print("[Pipeline] Text inserted")

        return text
    }
}
