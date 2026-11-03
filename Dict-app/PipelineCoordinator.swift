import AppKit
import Foundation
import os

@MainActor
final class PipelineCoordinator {
    let appleEngine = AppleSpeechTranscriptionService()
    let parakeetEngine = ParakeetTranscriptionService()
    let textInsertionService = TextInsertionService()
    let historyStore = HistoryStore()
    private let formatter = TranscriptFormatter()

    /// Mirrors the user's "Format Transcripts" setting; owned by AppState.
    var isFormattingEnabled = true

    /// Mirrors the user's dictation style; owned by AppState.
    var dictationStyle: DictationStyle = .verbatim

    /// Mirrors the user's "space after each dictation" setting; owned by AppState.
    var appendTrailingSpace = false

    /// Mirrors the user's "space before dictation when needed" setting; owned by AppState.
    var smartLeadingSpace = true

    /// Mirrors the user's word-replacement list; owned by AppState.
    var wordReplacements: [WordReplacement] = []

    /// Mirrors the user's transcription-engine setting; owned by AppState.
    var engineChoice: TranscriptionEngineChoice = .apple

    /// Mirrors the user's microphone setting; owned by AppState.
    var inputDeviceChoice: InputDeviceChoice = .automatic

    /// The microphone the next recording uses, given what's connected now.
    func resolvedInputDevice() -> AudioInputDevice? {
        InputDeviceSelection.resolve(
            inputDeviceChoice,
            devices: AudioInputDevices.all(),
            systemDefault: AudioInputDevices.systemDefault()
        )
    }

    var activeEngine: any TranscriptionEngine {
        switch engineChoice {
        case .apple: appleEngine
        case .parakeet: parakeetEngine
        }
    }

    /// The microphone the current recording uses; resolved once at start so
    /// the HUD can read it every frame without touching CoreAudio.
    private(set) var currentInputDevice: AudioInputDevice?

    /// Fired when the engine couldn't begin recording after the hotkey went
    /// down, so the app can end the session instead of waiting on silence.
    var onStartFailed: (() -> Void)?
    private var startFailed = false

    func startRecording() {
        let engine = activeEngine
        currentInputDevice = resolvedInputDevice()
        engine.inputDeviceID = currentInputDevice?.id
        startFailed = false
        Task {
            do {
                try await engine.start()
                Log.pipeline.info("Recording session started")
            } catch {
                Log.pipeline.error("Failed to start: \(String(describing: error), privacy: .public)")
                startFailed = true
                onStartFailed?()
            }
        }
    }

    /// The result a recording ends with before any formatting happens, or
    /// nil when there is text to format and insert.
    static func earlyResult(stop: Result<String, Error>, startFailed: Bool) -> DictationResult? {
        if startFailed { return .failed }
        switch stop {
        case .failure: return .failed
        case .success(let text): return text.isEmpty ? .nothingHeard : nil
        }
    }

    func cancelRecording() {
        activeEngine.cancel()
        Log.pipeline.info("Recording cancelled")
    }

    func stopRecordingAndProcess() async -> DictationResult {
        let stop: Result<String, Error>
        do {
            stop = .success(try await activeEngine.stop())
        } catch {
            Log.pipeline.error("Engine failed: \(String(describing: error), privacy: .public)")
            stop = .failure(error)
        }
        if let early = Self.earlyResult(stop: stop, startFailed: startFailed) {
            Log.pipeline.info("No text produced: \(String(describing: early), privacy: .public)")
            return early
        }
        guard case .success(let rawText) = stop else { return .failed }

        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let context: FormattingContext = CodingAppCatalog.isCodingApp(bundleID) ? .coding : .general
        let shouldFormat = Self.shouldFormat(enabled: isFormattingEnabled, engine: engineChoice, context: context, style: dictationStyle)
        let formatted: String
        if shouldFormat {
            formatted = await formatter.format(rawText, context: context, style: dictationStyle)
        } else if dictationStyle != .verbatim {
            formatted = FillerRemover.clean(rawText)
        } else {
            formatted = rawText
        }
        let text = WordReplacement.apply(wordReplacements, to: formatted)

        // Escape cancelled processing while we were transcribing/formatting.
        guard !Task.isCancelled else {
            Log.pipeline.info("Cancelled, discarding result")
            return .cancelled
        }

        historyStore.save(cleanedText: text)
        Log.pipeline.info("Saved to history. Inserting text...")
        // Add separator spaces to the inserted text only — History keeps
        // the clean text so the list stays tidy.
        var textToInsert = appendTrailingSpace ? text + " " : text
        if smartLeadingSpace,
           SmartSpacing.needsLeadingSpace(preceding: textInsertionService.characterBeforeCursor(), text: text) {
            textToInsert = " " + textToInsert
        }
        textInsertionService.insertText(textToInsert)
        Log.pipeline.info("Text inserted")

        return .inserted(text)
    }

    /// Parakeet already punctuates and capitalizes, so outside coding apps
    /// the LLM pass only adds latency and a chance of dropped words. In
    /// coding apps it still earns its keep fixing technical terms.
    static func shouldFormat(enabled: Bool, engine: TranscriptionEngineChoice, context: FormattingContext, style: DictationStyle = .verbatim) -> Bool {
        guard enabled else { return false }
        // Clean and Polished need the model whatever the engine.
        return style != .verbatim || engine != .parakeet || context == .coding
    }
}
