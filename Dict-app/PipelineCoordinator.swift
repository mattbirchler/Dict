import AppKit
import Foundation

@MainActor
final class PipelineCoordinator {
    let appleEngine = AppleSpeechTranscriptionService()
    let parakeetEngine = ParakeetTranscriptionService()
    let textInsertionService = TextInsertionService()
    let historyStore = HistoryStore()
    private let formatter = TranscriptFormatter()

    /// Mirrors the user's "Format Transcripts" setting; owned by AppState.
    var isFormattingEnabled = true

    /// Mirrors the user's "space after each dictation" setting; owned by AppState.
    var appendTrailingSpace = false

    /// Mirrors the user's "space before dictation when needed" setting; owned by AppState.
    var smartLeadingSpace = true

    /// Mirrors the user's word-replacement list; owned by AppState.
    var wordReplacements: [WordReplacement] = []

    /// Mirrors the user's transcription-engine setting; owned by AppState.
    var engineChoice: TranscriptionEngineChoice = .apple

    var activeEngine: any TranscriptionEngine {
        switch engineChoice {
        case .apple: appleEngine
        case .parakeet: parakeetEngine
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
        let shouldFormat = Self.shouldFormat(enabled: isFormattingEnabled, engine: engineChoice, context: context)
        let formatted = shouldFormat ? await formatter.format(rawText, context: context) : rawText
        let text = WordReplacement.apply(wordReplacements, to: formatted)

        // Escape cancelled processing while we were transcribing/formatting.
        guard !Task.isCancelled else {
            print("[Pipeline] Cancelled, discarding result")
            return nil
        }

        historyStore.save(cleanedText: text)
        print("[Pipeline] Saved to history. Inserting text...")
        // Add separator spaces to the inserted text only — History keeps
        // the clean text so the list stays tidy.
        var textToInsert = appendTrailingSpace ? text + " " : text
        if smartLeadingSpace,
           SmartSpacing.needsLeadingSpace(preceding: textInsertionService.characterBeforeCursor(), text: text) {
            textToInsert = " " + textToInsert
        }
        textInsertionService.insertText(textToInsert)
        print("[Pipeline] Text inserted")

        return text
    }

    /// Parakeet already punctuates and capitalizes, so outside coding apps
    /// the LLM pass only adds latency and a chance of dropped words. In
    /// coding apps it still earns its keep fixing technical terms.
    static func shouldFormat(enabled: Bool, engine: TranscriptionEngineChoice, context: FormattingContext) -> Bool {
        guard enabled else { return false }
        return engine != .parakeet || context == .coding
    }
}
