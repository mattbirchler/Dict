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
        let pipelineStarted = ProcessInfo.processInfo.systemUptime
        let transcriptionStarted = pipelineStarted
        let rawText = await activeEngine.stop()
        let transcriptionSeconds = ProcessInfo.processInfo.systemUptime - transcriptionStarted

        guard !rawText.isEmpty else {
            print("[Pipeline] No text produced, aborting")
            print(String(
                format: "[Timing] engine=%@ transcription=%.3fs total=%.3fs result=empty",
                engineChoice.displayName,
                transcriptionSeconds,
                ProcessInfo.processInfo.systemUptime - pipelineStarted
            ))
            return nil
        }

        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let context: FormattingContext = CodingAppCatalog.isCodingApp(bundleID) ? .coding : .general
        let formattingStarted = ProcessInfo.processInfo.systemUptime
        let text = isFormattingEnabled ? await formatter.format(rawText, context: context) : rawText
        let formattingSeconds = ProcessInfo.processInfo.systemUptime - formattingStarted

        let historyStarted = ProcessInfo.processInfo.systemUptime
        historyStore.save(cleanedText: text)
        let historySeconds = ProcessInfo.processInfo.systemUptime - historyStarted
        print("[Pipeline] Saved to history. Inserting text...")
        // Append the separator space to the inserted text only — History keeps
        // the clean text so the list stays tidy.
        let textToInsert = appendTrailingSpace ? text + " " : text
        let insertionStarted = ProcessInfo.processInfo.systemUptime
        await textInsertionService.insertText(textToInsert)
        let insertionSeconds = ProcessInfo.processInfo.systemUptime - insertionStarted
        print("[Pipeline] Text inserted")
        print(String(
            format: "[Timing] engine=%@ transcription=%.3fs formatting=%.3fs history=%.3fs insertion=%.3fs total=%.3fs chars=%d",
            engineChoice.displayName,
            transcriptionSeconds,
            formattingSeconds,
            historySeconds,
            insertionSeconds,
            ProcessInfo.processInfo.systemUptime - pipelineStarted,
            text.count
        ))

        return text
    }
}
