import AppKit
import Foundation
import os

@MainActor
final class PipelineCoordinator {
    let appleEngine = AppleSpeechTranscriptionService()
    let parakeetEngine = ParakeetTranscriptionService()
    let textInsertionService = TextInsertionService()
    let historyStore = HUDPreview.sampleHistoryStore() ?? HistoryStore()
    private let formatter = TranscriptFormatter()

    /// Mirrors the user's "Format Transcripts" setting; owned by AppState.
    var isFormattingEnabled = true

    /// Mirrors the user's dictation style; owned by AppState.
    var dictationStyle: DictationStyle = .verbatim

    /// Mirrors the user's screen-context setting; owned by AppState.
    var usesScreenContext = true

    /// Mirrors the user's live-insertion setting; owned by AppState.
    var insertsLiveWords = false
    /// Polls the engine's confirmed words into the field while recording.
    private var liveInserter: LiveInserter?
    private var liveInsertionTask: Task<Void, Never>?
    static let liveInsertionInterval: Duration = .milliseconds(150)

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
        // Electron apps need a moment to build their accessibility tree;
        // start it now so smart spacing can read the cursor later.
        FocusedElement.prepareFrontmostApp()
        if insertsLiveWords, engine.supportsLiveTranscript {
            beginLiveInsertion(engine: engine)
        }
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
        endLiveInsertion()?.cancel()
        Log.pipeline.info("Recording cancelled")
    }

    /// Types confirmed words as they arrive. The engine's preview is
    /// started here because, for Parakeet, it costs a decode every 700 ms.
    private func beginLiveInsertion(engine: any TranscriptionEngine) {
        engine.beginLivePreview()
        let inserter = LiveInserter(insertion: textInsertionService, smartLeadingSpace: smartLeadingSpace)
        liveInserter = inserter
        liveInsertionTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.liveInsertionInterval)
                guard let self, !Task.isCancelled, self.liveInserter === inserter else { return }
                inserter.update(confirmed: engine.liveTranscript.confirmed)
            }
        }
    }

    /// Stops the polling and hands back the inserter so the caller can
    /// finish or cancel what it typed.
    private func endLiveInsertion() -> LiveInserter? {
        liveInsertionTask?.cancel()
        liveInsertionTask = nil
        defer { liveInserter = nil }
        return liveInserter
    }

    func stopRecordingAndProcess() async -> DictationResult {
        let inserter = endLiveInsertion()
        let result = await stopAndProcess(liveInserter: inserter)
        if case .inserted = result {} else {
            // Nothing final went in; take back whatever was typed live.
            inserter?.cancel()
        }
        return result
    }

    private func stopAndProcess(liveInserter: LiveInserter?) async -> DictationResult {
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
        // Names and terms already in the document, so the dictation spells
        // them the same way. Read once, used by the formatter and the
        // respelling pass below.
        let terms = usesScreenContext ? ScreenContext.extractTerms(from: ScreenContext.focusedText() ?? "") : []
        let formatted: String
        if shouldFormat {
            formatted = await formatter.format(rawText, context: context, style: dictationStyle, terms: terms)
        } else if dictationStyle != .verbatim {
            formatted = FillerRemover.clean(rawText)
        } else {
            formatted = rawText
        }
        // Spoken numbers become digits in every style, since the engines
        // spell most of them out. Runs whether or not the formatter did
        // (it's skipped for most Parakeet dictations), as does the
        // respelling, and both come before word replacements so the
        // user's own rules still win.
        let numbered = NumberNormalizer.apply(formatted)
        let respelled = ScreenContextSpelling.apply(
            terms: terms,
            to: numbered,
            isDictionaryWord: ScreenContextSpelling.systemDictionaryContains
        )
        if usesScreenContext {
            Log.pipeline.info("Screen context: \(terms.count, privacy: .public) terms, \(respelled.fixes, privacy: .public) respelled")
        }
        let text = WordReplacement.apply(wordReplacements, to: respelled.text)

        // Escape cancelled processing while we were transcribing/formatting.
        guard !Task.isCancelled else {
            Log.pipeline.info("Cancelled, discarding result")
            return .cancelled
        }

        historyStore.save(cleanedText: text)
        Log.pipeline.info("Saved to history. Inserting text...")
        // Add separator spaces to the inserted text only — History keeps
        // the clean text so the list stays tidy.
        if let liveInserter {
            var textToInsert = appendTrailingSpace ? text + " " : text
            // The field already holds the live words; the leading-space
            // decision was made when the first of them went in.
            if liveInserter.insertedLeadingSpace { textToInsert = " " + textToInsert }
            liveInserter.finish(with: textToInsert)
            Log.pipeline.info("Live text reconciled")
        } else {
            insertSpaced(text)
            Log.pipeline.info("Text inserted")
        }

        return .inserted(text)
    }

    /// Pastes `text` into the focused field with the same spacing a new
    /// dictation gets. Used for dictations and for inserting one again from
    /// the menu bar.
    func insertSpaced(_ text: String) {
        var textToInsert = appendTrailingSpace ? text + " " : text
        if smartLeadingSpace,
           SmartSpacing.needsLeadingSpace(preceding: textInsertionService.characterBeforeCursor(), text: text) {
            textToInsert = " " + textToInsert
        }
        textInsertionService.insertText(textToInsert)
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
