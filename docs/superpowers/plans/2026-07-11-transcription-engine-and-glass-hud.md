# Transcription Engine Choice + Liquid Glass HUD — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Liquid Glass recording HUD and let users choose between WhisperKit and Apple's on-device SpeechAnalyzer engine, selectable at onboarding and in Settings.

**Architecture:** A `TranscriptionEngine` protocol abstracts the two engines; `PipelineCoordinator` holds both and routes recording to the active one per `SettingsStore.transcriptionEngine`. `AppState` mirrors the active engine's readiness as its own observable state so SwiftUI never observes a type-erased existential. The HUD change is an isolated material swap.

**Tech Stack:** Swift/SwiftUI/AppKit, WhisperKit, Apple `Speech` framework (`SpeechAnalyzer`/`SpeechTranscriber`), `AVFoundation`.

## Global Constraints

- Deployment target macOS 26.4; fully on-device (no servers).
- New `.swift` files under `Dict-app/` and `Dict-appTests/` are auto-included via `PBXFileSystemSynchronizedRootGroup` — do NOT edit `project.pbxproj` to add files.
- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`) — never XCTest.
- Build/verify with: `xcodebuild -project Dict-app.xcodeproj -scheme Dict-app -destination 'platform=macOS' build`
- Test with: `xcodebuild -project Dict-app.xcodeproj -scheme Dict-app -destination 'platform=macOS' test`
- The module compiles under default main-actor isolation (`SWIFT_APPROACHABLE_CONCURRENCY = YES`).
- `NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription` already exist as `INFOPLIST_KEY_*` build settings; `PermissionChecker` already handles speech-recognition authorization. No Info.plist/permission changes required.
- SpeechAnalyzer API details: see `docs/superpowers/specs/2026-07-11-speechanalyzer-api-reference.md`.

---

### Task 1: Liquid Glass HUD (Feature A)

**Files:**
- Modify: `Dict-app/WaveformHUD.swift:60`

**Interfaces:**
- Consumes: nothing new.
- Produces: nothing consumed by later tasks. Fully independent.

- [ ] **Step 1: Swap the material for Liquid Glass**

In `Dict-app/WaveformHUD.swift`, in `WaveformHUD.body`, replace this line:

```swift
        .background(.ultraThinMaterial, in: Capsule())
```

with:

```swift
        .glassEffect(.regular, in: .capsule)
```

Leave every other line (layout, padding, dot, waveform, label) unchanged. `.glassEffect` stays last in the modifier chain, after the two `.padding` modifiers.

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -project Dict-app.xcodeproj -scheme Dict-app -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Dict-app/WaveformHUD.swift
git commit -m "feat: Liquid Glass recording HUD"
```

---

### Task 2: SettingsStore engine choice + migration (Feature B)

**Files:**
- Modify: `Dict-app/SettingsStore.swift`
- Test: `Dict-appTests/SettingsStoreTests.swift`

**Interfaces:**
- Produces: `enum TranscriptionEngineChoice: String, CaseIterable { case apple, whisper }` with `displayName: String` and `blurb: String`; `SettingsStore.transcriptionEngine: TranscriptionEngineChoice`; new `SettingsStore.Change` case `.transcriptionEngine`.

- [ ] **Step 1: Write the failing tests**

Add to `Dict-appTests/SettingsStoreTests.swift`:

```swift
    @Test func defaultEngineIsAppleOnFreshInstall() {
        let store = SettingsStore(defaults: makeDefaults())
        #expect(store.transcriptionEngine == .apple)
    }

    @Test func existingUserMigratesToWhisper() {
        // An upgrading user has already completed onboarding but has no engine
        // key yet — they must keep Whisper, not be moved onto Apple.
        let defaults = makeDefaults()
        defaults.set(true, forKey: "hasCompletedOnboarding")
        let store = SettingsStore(defaults: defaults)
        #expect(store.transcriptionEngine == .whisper)
    }

    @Test func enginePersistsAndReloads() {
        let defaults = makeDefaults()
        let store = SettingsStore(defaults: defaults)
        store.transcriptionEngine = .whisper
        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.transcriptionEngine == .whisper)
    }

    @Test func firesOnChangeForEngine() {
        let store = SettingsStore(defaults: makeDefaults())
        var changes: [SettingsStore.Change] = []
        store.onChange = { changes.append($0) }
        store.transcriptionEngine = .whisper
        #expect(changes == [.transcriptionEngine])
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -project Dict-app.xcodeproj -scheme Dict-app -destination 'platform=macOS' test 2>&1 | grep -i "transcriptionEngine\|error:"`
Expected: compile failure — `transcriptionEngine` / `.transcriptionEngine` do not exist yet.

- [ ] **Step 3: Add the enum**

In `Dict-app/SettingsStore.swift`, after the `HistoryLimit` enum, add:

```swift
enum TranscriptionEngineChoice: String, CaseIterable {
    case apple, whisper

    var displayName: String {
        switch self {
        case .apple: "Apple"
        case .whisper: "Whisper"
        }
    }

    /// One-line tradeoff shown in onboarding / settings.
    var blurb: String {
        switch self {
        case .apple: "Fast, already on your Mac. No download."
        case .whisper: "More accurate, slower. ~1 GB download."
        }
    }
}
```

- [ ] **Step 4: Add the Change case, key, property, and migration**

In `SettingsStore`, extend the `Change` enum:

```swift
    enum Change { case hotkey, activationMode, formatting, historyLimit, transcriptionEngine }
```

Add to `private enum Keys`:

```swift
        static let transcriptionEngine = "transcriptionEngine"
```

Add the stored property (place it after `historyLimit`):

```swift
    var transcriptionEngine: TranscriptionEngineChoice {
        didSet {
            defaults.set(transcriptionEngine.rawValue, forKey: Keys.transcriptionEngine)
            onChange?(.transcriptionEngine)
        }
    }
```

In `init(defaults:)`, after the `historyLimit` assignment, add the migration:

```swift
        if let raw = defaults.string(forKey: Keys.transcriptionEngine),
           let choice = TranscriptionEngineChoice(rawValue: raw) {
            self.transcriptionEngine = choice
        } else if defaults.bool(forKey: "hasCompletedOnboarding") {
            // Existing user upgrading: keep Whisper so nothing changes for them.
            self.transcriptionEngine = .whisper
        } else {
            // Fresh install: default to Apple (no 1 GB download to get started).
            self.transcriptionEngine = .apple
        }
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `xcodebuild -project Dict-app.xcodeproj -scheme Dict-app -destination 'platform=macOS' test 2>&1 | tail -20`
Expected: all SettingsStore tests pass.

- [ ] **Step 6: Commit**

```bash
git add Dict-app/SettingsStore.swift Dict-appTests/SettingsStoreTests.swift
git commit -m "feat: transcription engine setting with fresh-install/upgrade migration"
```

---

### Task 3: TranscriptionEngine protocol + WhisperKit conformance

**Files:**
- Create: `Dict-app/TranscriptionEngine.swift`
- Modify: `Dict-app/StreamingTranscriptionService.swift`

**Interfaces:**
- Produces: `protocol TranscriptionEngine` (see below) used by Tasks 4, 5, 6.
- Consumes: existing `StreamingTranscriptionService` members `audioEnergy`, `isRecording`, `isModelLoaded`, `ensureLoaded()`, `start()`, `cancel()`, `stop()`, `onProgress`.

- [ ] **Step 1: Create the protocol**

Create `Dict-app/TranscriptionEngine.swift`:

```swift
import Foundation

/// A pluggable on-device transcription engine. Both WhisperKit and Apple's
/// SpeechAnalyzer sit behind this so the pipeline can switch between them.
/// Class-bound (`AnyObject`) so the pipeline holds a shared reference.
@MainActor
protocol TranscriptionEngine: AnyObject {
    /// Trailing rolling buffer of recent audio levels; the HUD reads `.last`
    /// (normalized ~0...1) to drive the waveform.
    var audioEnergy: [Float] { get }

    var isRecording: Bool { get }

    /// True once the engine's model/assets are installed and loaded so
    /// recording can begin immediately.
    var isReady: Bool { get }

    /// True when this engine has a user-visible download step before it is
    /// usable (Whisper). Apple reports false unless a first-time asset install
    /// is genuinely in progress.
    var needsDownload: Bool { get }

    /// Download/prepare progress callback (0...1), invoked during `prepare()`.
    var onProgress: ((Double) -> Void)? { get set }

    /// Idempotent: download/install and load whatever the engine needs.
    func prepare() async throws

    func start() async throws
    func cancel()
    func stop() async -> String
}
```

- [ ] **Step 2: Conform StreamingTranscriptionService**

At the end of `Dict-app/StreamingTranscriptionService.swift` (after the class, before or after the error enum), add:

```swift
extension StreamingTranscriptionService: TranscriptionEngine {
    var isReady: Bool { isModelLoaded }
    var needsDownload: Bool { true }
    func prepare() async throws { try await ensureLoaded() }
}
```

`audioEnergy`, `isRecording`, `start()`, `cancel()`, `stop()`, and `onProgress` already satisfy the protocol.

- [ ] **Step 3: Build to verify conformance compiles**

Run: `xcodebuild -project Dict-app.xcodeproj -scheme Dict-app -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Dict-app/TranscriptionEngine.swift Dict-app/StreamingTranscriptionService.swift
git commit -m "feat: TranscriptionEngine protocol; WhisperKit conforms"
```

---

### Task 4: AppleSpeechTranscriptionService

**Files:**
- Create: `Dict-app/AppleSpeechTranscriptionService.swift`
- Test: `Dict-appTests/AppleSpeechTranscriptionServiceTests.swift`

**Interfaces:**
- Consumes: `TranscriptionEngine` (Task 3).
- Produces: `final class AppleSpeechTranscriptionService: TranscriptionEngine`, plus `nonisolated static` helpers `rms(_:) -> Float`, `normalizedEnergy(rms:) -> Float`, `plainText(_:) -> String` used by tests.

Reference the SpeechAnalyzer API doc while implementing: `docs/superpowers/specs/2026-07-11-speechanalyzer-api-reference.md`.

- [ ] **Step 1: Write the failing unit tests**

Create `Dict-appTests/AppleSpeechTranscriptionServiceTests.swift`:

```swift
import Foundation
import Testing
@testable import Dict_app

@MainActor
struct AppleSpeechTranscriptionServiceTests {
    @Test func rmsOfSilenceIsZero() {
        let silence = [Float](repeating: 0, count: 512)
        #expect(AppleSpeechTranscriptionService.rms(silence) == 0)
    }

    @Test func rmsOfConstantSignal() {
        let ones = [Float](repeating: 0.5, count: 100)
        // RMS of a constant 0.5 signal is 0.5.
        #expect(abs(AppleSpeechTranscriptionService.rms(ones) - 0.5) < 0.0001)
    }

    @Test func rmsOfEmptyIsZero() {
        #expect(AppleSpeechTranscriptionService.rms([]) == 0)
    }

    @Test func normalizedEnergyIsClampedAndMonotonic() {
        #expect(AppleSpeechTranscriptionService.normalizedEnergy(rms: 0) == 0)
        let mid = AppleSpeechTranscriptionService.normalizedEnergy(rms: 0.1)
        let hi = AppleSpeechTranscriptionService.normalizedEnergy(rms: 0.5)
        #expect(mid > 0)
        #expect(hi >= mid)
        #expect(hi <= 1)
        // Very loud input clamps to 1, never above.
        #expect(AppleSpeechTranscriptionService.normalizedEnergy(rms: 5) == 1)
    }

    @Test func plainTextExtractsCharacters() {
        let attributed = AttributedString("hello world")
        #expect(AppleSpeechTranscriptionService.plainText(attributed) == "hello world")
    }

    @Test func startsNotReadyAndNotRecording() {
        let service = AppleSpeechTranscriptionService()
        #expect(service.isReady == false)
        #expect(service.isRecording == false)
        #expect(service.needsDownload == false)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `xcodebuild -project Dict-app.xcodeproj -scheme Dict-app -destination 'platform=macOS' test 2>&1 | grep -i "AppleSpeech\|error:"`
Expected: compile failure — the class does not exist.

- [ ] **Step 3: Implement the service**

Create `Dict-app/AppleSpeechTranscriptionService.swift`:

```swift
import Foundation
import AVFoundation
import Speech

/// On-device transcription using Apple's SpeechAnalyzer/SpeechTranscriber
/// (macOS 26). Owns its own AVAudioEngine tap; feeds converted buffers into a
/// SpeechAnalyzer streaming session and returns the finalized transcript on
/// stop. English-only (en-US) to match the current Whisper path.
@MainActor
@Observable
final class AppleSpeechTranscriptionService: TranscriptionEngine {
    var audioEnergy: [Float] = []
    private(set) var isRecording: Bool = false
    private(set) var isReady: Bool = false
    private(set) var needsDownload: Bool = false
    @ObservationIgnored var onProgress: ((Double) -> Void)?

    private let locale = Locale(identifier: "en-US")
    private let maxEnergySamples = 64

    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var analyzerFormat: AVAudioFormat?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var finalizedText = AttributedString()
    private let audioEngine = AVAudioEngine()

    // MARK: - Prepare (asset install)

    func prepare() async throws {
        if isReady { return }
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        self.transcriber = transcriber

        let supported = await SpeechTranscriber.supportedLocales.contains {
            $0.identifier(.bcp47) == locale.identifier(.bcp47)
        }
        guard supported else { throw AppleSpeechError.localeUnsupported }

        let installed = await SpeechTranscriber.installedLocales.contains {
            $0.identifier(.bcp47) == locale.identifier(.bcp47)
        }
        if !installed {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                needsDownload = true
                let observation = request.progress.observe(\.fractionCompleted, options: [.initial, .new]) { [weak self] progress, _ in
                    let fraction = progress.fractionCompleted
                    Task { @MainActor in self?.onProgress?(fraction) }
                }
                defer { observation.invalidate() }
                try await request.downloadAndInstall()
                needsDownload = false
            }
        }

        analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        isReady = true
    }

    // MARK: - Recording lifecycle

    func start() async throws {
        guard !isRecording else { return }
        guard isReady, let transcriber, let analyzerFormat else {
            throw AppleSpeechError.notPrepared
        }
        finalizedText = AttributedString()
        audioEnergy = []

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer

        let (inputSequence, builder) = AsyncStream<AnalyzerInput>.makeStream()
        self.inputBuilder = builder

        // Drain results on the main actor (this Task inherits main-actor
        // isolation); accumulate only finalized text.
        resultsTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await result in transcriber.results {
                    if result.isFinal {
                        self.finalizedText += result.text
                    }
                }
            } catch {
                print("[AppleSpeech] results stream error: \(error)")
            }
        }

        // Install the mic tap. The callback runs on a realtime audio thread:
        // capture Sendable/local values, never touch main-actor state directly
        // (energy is published via a MainActor Task hop).
        let tapFormat = audioEngine.inputNode.outputFormat(forBus: 0)
        nonisolated(unsafe) let converter = AVAudioConverter(from: tapFormat, to: analyzerFormat)
        let format = analyzerFormat
        audioEngine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { [weak self] buffer, _ in
            let level = Self.rmsLevel(buffer)
            Task { @MainActor [weak self] in self?.appendEnergy(level) }
            if let converter, let converted = Self.convert(buffer, using: converter, to: format) {
                builder.yield(AnalyzerInput(buffer: converted))
            }
        }
        audioEngine.prepare()
        try audioEngine.start()

        try await analyzer.start(inputSequence: inputSequence)
        isRecording = true
        print("[AppleSpeech] Recording started")
    }

    func cancel() {
        guard isRecording else { return }
        isRecording = false
        teardownAudio()
        resultsTask?.cancel()
        resultsTask = nil
        let analyzer = self.analyzer
        self.analyzer = nil
        finalizedText = AttributedString()
        audioEnergy = []
        Task { await analyzer?.cancelAndFinishNow() }
        print("[AppleSpeech] Recording cancelled")
    }

    func stop() async -> String {
        guard isRecording else { return "" }
        isRecording = false
        teardownAudio()

        do {
            try await analyzer?.finalizeAndFinishThroughEndOfInput()
        } catch {
            print("[AppleSpeech] finalize error: \(error)")
        }
        // Let the results task drain the remaining finalized results.
        await resultsTask?.value
        resultsTask = nil
        analyzer = nil
        audioEnergy = []

        let text = Self.plainText(finalizedText).trimmingCharacters(in: .whitespacesAndNewlines)
        finalizedText = AttributedString()
        print("[AppleSpeech] Result: \"\(text)\"")
        return text
    }

    private func teardownAudio() {
        audioEngine.inputNode.removeTap(onBus: 0)
        if audioEngine.isRunning { audioEngine.stop() }
        inputBuilder?.finish()
        inputBuilder = nil
    }

    private func appendEnergy(_ level: Float) {
        audioEnergy.append(Self.normalizedEnergy(rms: level))
        if audioEnergy.count > maxEnergySamples {
            audioEnergy.removeFirst(audioEnergy.count - maxEnergySamples)
        }
    }

    // MARK: - Pure helpers (testable)

    /// RMS of a raw sample array. 0 for empty/silence.
    nonisolated static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sumSquares = samples.reduce(Float(0)) { $0 + $1 * $1 }
        return (sumSquares / Float(samples.count)).squareRoot()
    }

    /// Maps an RMS level (~0...0.3 for speech) into the 0...1 range the HUD
    /// waveform expects. Gain is tuned so normal speech lifts the bars; loud
    /// input clamps at 1.
    nonisolated static func normalizedEnergy(rms: Float) -> Float {
        min(max(rms * 6, 0), 1)
    }

    nonisolated static func plainText(_ attributed: AttributedString) -> String {
        String(attributed.characters)
    }

    /// RMS of the first channel of a PCM buffer.
    nonisolated static func rmsLevel(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<count { let s = channel[i]; sum += s * s }
        return (sum / Float(count)).squareRoot()
    }

    /// Sample-rate-aware conversion from the tap format to the analyzer format.
    nonisolated static func convert(_ buffer: AVAudioPCMBuffer,
                                    using converter: AVAudioConverter,
                                    to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var supplied = false
        var err: NSError?
        converter.convert(to: out, error: &err) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        return err == nil ? out : nil
    }
}

enum AppleSpeechError: LocalizedError {
    case localeUnsupported
    case notPrepared

    var errorDescription: String? {
        switch self {
        case .localeUnsupported: "This language isn't supported by Apple's on-device speech engine."
        case .notPrepared: "The Apple speech engine isn't ready yet."
        }
    }
}
```

**Concurrency note for the implementer:** the module builds under default main-actor isolation. If the tap-closure capture of `converter`/`builder`/`format` or the `Task { @MainActor }` hop produces a strict-concurrency error, resolve it while preserving the realtime-safe pattern (no `await` inside the tap; publish energy only via the MainActor hop; yield converted buffers to the stream). Do not move transcription work onto the audio thread. If `.observe(\.fractionCompleted, ...)` on `Progress` is unavailable, substitute the supported progress-observation call from the API reference doc; the download must still complete via `downloadAndInstall()`.

- [ ] **Step 4: Run the unit tests to verify they pass**

Run: `xcodebuild -project Dict-app.xcodeproj -scheme Dict-app -destination 'platform=macOS' test 2>&1 | tail -20`
Expected: the `AppleSpeechTranscriptionServiceTests` pass. (These cover only the pure helpers + initial state — no live audio.)

- [ ] **Step 5: Commit**

```bash
git add Dict-app/AppleSpeechTranscriptionService.swift Dict-appTests/AppleSpeechTranscriptionServiceTests.swift
git commit -m "feat: Apple SpeechAnalyzer transcription engine"
```

---

### Task 5: PipelineCoordinator two-engine routing

**Files:**
- Modify: `Dict-app/PipelineCoordinator.swift`
- Test: `Dict-appTests/PipelineEngineSelectionTests.swift`

**Interfaces:**
- Consumes: `TranscriptionEngine` (Task 3), `TranscriptionEngineChoice` (Task 2), `AppleSpeechTranscriptionService` (Task 4).
- Produces: `PipelineCoordinator.whisperEngine`, `.appleEngine`, `.engineChoice: TranscriptionEngineChoice`, computed `.activeEngine: any TranscriptionEngine`.

- [ ] **Step 1: Write the failing test**

Create `Dict-appTests/PipelineEngineSelectionTests.swift`:

```swift
import Foundation
import Testing
@testable import Dict_app

@MainActor
struct PipelineEngineSelectionTests {
    @Test func activeEngineFollowsChoice() {
        let pipeline = PipelineCoordinator()

        pipeline.engineChoice = .apple
        #expect(pipeline.activeEngine === pipeline.appleEngine)

        pipeline.engineChoice = .whisper
        #expect(pipeline.activeEngine === pipeline.whisperEngine)
    }

    @Test func defaultChoiceIsApple() {
        let pipeline = PipelineCoordinator()
        #expect(pipeline.engineChoice == .apple)
        #expect(pipeline.activeEngine === pipeline.appleEngine)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `xcodebuild -project Dict-app.xcodeproj -scheme Dict-app -destination 'platform=macOS' test 2>&1 | grep -i "PipelineEngine\|error:"`
Expected: compile failure — `engineChoice`/`activeEngine`/`appleEngine`/`whisperEngine` don't exist.

- [ ] **Step 3: Rewrite PipelineCoordinator**

Replace the body of `Dict-app/PipelineCoordinator.swift` with:

```swift
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild -project Dict-app.xcodeproj -scheme Dict-app -destination 'platform=macOS' test 2>&1 | tail -20`
Expected: `PipelineEngineSelectionTests` pass. NOTE: this task will not fully build until Task 6 updates `AppState`/`Dict_appApp` references to the old `transcriptionService`/`preloadWhisperModel`. If the build fails only on those symbols in `AppState.swift`/`Dict_appApp.swift`/`OnboardingWindow.swift`, that is expected and resolved in Tasks 6–8; run the SettingsStore/Pipeline/AppleSpeech unit tests are green once Task 6 lands. To keep Task 5 independently green, do Step 5 commit now and let Task 6 restore a building tree.

- [ ] **Step 5: Commit**

```bash
git add Dict-app/PipelineCoordinator.swift Dict-appTests/PipelineEngineSelectionTests.swift
git commit -m "feat: pipeline routes recording to the selected engine"
```

---

### Task 6: AppState mirrored readiness + engine switching + call sites

**Files:**
- Modify: `Dict-app/AppState.swift`
- Modify: `Dict-app/Dict_appApp.swift`

**Interfaces:**
- Consumes: `PipelineCoordinator.activeEngine`/`engineChoice` (Task 5), `SettingsStore.transcriptionEngine` + `.transcriptionEngine` Change (Task 2).
- Produces: `AppState.isEngineReady`, `.engineNeedsDownload`, `.isPreparingEngine`, `.engineDownloadProgress`, `.prepareEngine()`, `.refreshEngineReadiness()`. Removes `isLoadingWhisper`, `whisperDownloadProgress`, `preloadWhisperModel()`.

- [ ] **Step 1: Rewrite AppState**

Replace `Dict-app/AppState.swift` with:

```swift
import Foundation

@MainActor
@Observable
final class AppState {
    let settings: SettingsStore
    let permissionChecker = PermissionChecker()
    let pipeline = PipelineCoordinator()

    var isEnabled = true {
        didSet { onEnabledChanged?(isEnabled) }
    }
    var onEnabledChanged: ((Bool) -> Void)?
    var onProcessingComplete: (() -> Void)?
    var onHotkeySettingsChanged: (() -> Void)?
    var isRecording = false
    var isProcessing = false

    // Mirror of the active engine's readiness, so SwiftUI observes concrete
    // AppState state rather than a type-erased TranscriptionEngine existential.
    var isPreparingEngine = false
    var isEngineReady = false
    var engineNeedsDownload = false
    var engineDownloadProgress: Double = 0

    var lastError: String?
    var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") }
        set { UserDefaults.standard.set(newValue, forKey: "hasCompletedOnboarding") }
    }

    init(settings: SettingsStore) {
        self.settings = settings
        pipeline.isFormattingEnabled = settings.isFormattingEnabled
        pipeline.historyStore.limit = settings.historyLimit
        pipeline.engineChoice = settings.transcriptionEngine
        refreshEngineReadiness()
        settings.onChange = { [weak self] change in
            guard let self else { return }
            switch change {
            case .formatting:
                self.pipeline.isFormattingEnabled = self.settings.isFormattingEnabled
            case .historyLimit:
                self.pipeline.historyStore.limit = self.settings.historyLimit
            case .hotkey, .activationMode:
                self.onHotkeySettingsChanged?()
            case .transcriptionEngine:
                self.handleEngineChange()
            }
        }
    }

    /// Read readiness from the active engine without starting any work.
    func refreshEngineReadiness() {
        let engine = pipeline.activeEngine
        isEngineReady = engine.isReady
        engineNeedsDownload = engine.needsDownload && !engine.isReady
    }

    private func handleEngineChange() {
        pipeline.engineChoice = settings.transcriptionEngine
        engineDownloadProgress = 0
        refreshEngineReadiness()
        // Apple prepares cheaply (no big download) — do it automatically.
        // Whisper's 1 GB download stays explicit (user taps Download in the UI).
        if settings.transcriptionEngine == .apple && !isEngineReady {
            prepareEngine()
        }
    }

    /// Download/install + load the active engine, mirroring progress/readiness.
    func prepareEngine() {
        guard !isPreparingEngine else { return }
        let engine = pipeline.activeEngine
        if engine.isReady {
            refreshEngineReadiness()
            return
        }
        isPreparingEngine = true
        engineDownloadProgress = 0
        engineNeedsDownload = engine.needsDownload
        engine.onProgress = { [weak self] progress in
            self?.engineDownloadProgress = progress
        }
        Task {
            do {
                try await engine.prepare()
            } catch {
                print("[AppState] Engine failed to prepare: \(error)")
                lastError = "Speech engine failed to prepare."
            }
            isPreparingEngine = false
            refreshEngineReadiness()
            engine.onProgress = nil
        }
    }

    func startRecording() {
        guard isEnabled, !isRecording, !isProcessing, !isPreparingEngine else { return }
        isRecording = true
        lastError = nil
        pipeline.startRecording()
    }

    func cancelRecording() {
        guard isRecording else { return }
        isRecording = false
        pipeline.cancelRecording()
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        isProcessing = true

        Task {
            let result = await pipeline.stopRecordingAndProcess()
            isProcessing = false
            onProcessingComplete?()
            if result == nil {
                lastError = "Transcription failed. Please try again."
            }
        }
    }
}
```

- [ ] **Step 2: Update Dict_appApp call sites**

In `Dict-app/Dict_appApp.swift`:

Change the HUD audio-level closure source from the Whisper service to the active engine. Replace:

```swift
                    let energy = self?.appState.pipeline.transcriptionService.audioEnergy ?? []
```

with:

```swift
                    let energy = self?.appState.pipeline.activeEngine.audioEnergy ?? []
```

Replace the preload call in `applicationDidFinishLaunching`. Change:

```swift
        if !appState.hasCompletedOnboarding {
            onboardingController.show(appState: appState)
        } else {
            appState.preloadWhisperModel()
        }
```

to:

```swift
        if !appState.hasCompletedOnboarding {
            onboardingController.show(appState: appState)
        } else {
            appState.prepareEngine()
        }
```

(The `StreamingTranscriptionService.inputDeviceName` mic-name closure is engine-agnostic — leave it unchanged.)

- [ ] **Step 3: Build to verify the tree compiles again**

Run: `xcodebuild -project Dict-app.xcodeproj -scheme Dict-app -destination 'platform=macOS' build 2>&1 | tail -8`
Expected: `** BUILD SUCCEEDED **`. If `OnboardingWindow.swift` or `SettingsView.swift` still reference removed symbols (`isLoadingWhisper`, `whisperDownloadProgress`, `preloadWhisperModel`, `transcriptionService.isModelLoaded`), those are fixed in Tasks 7–8. If the ONLY remaining errors are in those two view files, proceed to Task 7; otherwise fix here.

- [ ] **Step 4: Run the full unit suite**

Run: `xcodebuild -project Dict-app.xcodeproj -scheme Dict-app -destination 'platform=macOS' test 2>&1 | tail -20`
Expected: SettingsStore, Pipeline, AppleSpeech, and existing tests pass (once Tasks 7–8 restore the view files if the build was blocked). If the build is blocked only by the view files, complete Task 7 first, then re-run.

- [ ] **Step 5: Commit**

```bash
git add Dict-app/AppState.swift Dict-app/Dict_appApp.swift
git commit -m "feat: AppState mirrors engine readiness and switches engines"
```

---

### Task 7: Onboarding engine picker + adaptive readiness row

**Files:**
- Modify: `Dict-app/OnboardingWindow.swift`

**Interfaces:**
- Consumes: `settings.transcriptionEngine` (Task 2), `AppState.isEngineReady`/`isPreparingEngine`/`engineNeedsDownload`/`engineDownloadProgress`/`prepareEngine()`/`refreshEngineReadiness()` (Task 6).

- [ ] **Step 1: Add the engine picker + adaptive readiness row**

In `Dict-app/OnboardingView`, add `@Bindable var appState` already exists. Insert an engine picker above the readiness row, and replace the Whisper-specific "Whisper Model" download `HStack` (currently the block starting `// WhisperKit model download`) with an adaptive row driven by `appState`.

Add this picker inside the `VStack(spacing: 16)` block, before the model row:

```swift
                VStack(alignment: .leading, spacing: 8) {
                    Text("Transcription engine")
                        .font(.headline)
                    Picker("", selection: Binding(
                        get: { appState.settings.transcriptionEngine },
                        set: { appState.settings.transcriptionEngine = $0 }
                    )) {
                        ForEach(TranscriptionEngineChoice.allCases, id: \.self) { choice in
                            Text(choice.displayName).tag(choice)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text(appState.settings.transcriptionEngine.blurb)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.05)))
```

Replace the entire `// WhisperKit model download` `HStack { ... }` block (through its `.background(...)`) with:

```swift
                // Adaptive engine-readiness row
                HStack(spacing: 12) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title2)
                        .foregroundStyle(appState.isEngineReady ? .green : .secondary)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(appState.settings.transcriptionEngine == .whisper ? "Whisper Model" : "Apple Speech")
                            .font(.headline)
                        if appState.isEngineReady {
                            Text("Ready")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if appState.isPreparingEngine {
                            if appState.settings.transcriptionEngine == .whisper {
                                ProgressView(value: appState.engineDownloadProgress)
                                    .progressViewStyle(.linear)
                            } else {
                                Text("Preparing…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else if appState.settings.transcriptionEngine == .whisper {
                            Text("Download speech model (~1 GB)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Preparing…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if appState.isEngineReady {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.title2)
                    } else if appState.isPreparingEngine {
                        ProgressView()
                            .controlSize(.small)
                    } else if appState.settings.transcriptionEngine == .whisper {
                        Button("Download") { appState.prepareEngine() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(appState.isEngineReady ? Color.green.opacity(0.05) : Color.secondary.opacity(0.05))
                )
```

- [ ] **Step 2: Update the "Get Started" gate and add engine sync**

Replace the `Button("Get Started")` `.disabled(...)` modifier. Change:

```swift
            .disabled(!appState.pipeline.transcriptionService.isModelLoaded)
```

to:

```swift
            .disabled(!appState.isEngineReady)
```

And update the trailing guidance `if` condition. Change:

```swift
            if !appState.permissionChecker.allGranted || !appState.pipeline.transcriptionService.isModelLoaded {
```

to:

```swift
            if !appState.permissionChecker.allGranted || !appState.isEngineReady {
```

In the `.onAppear` at the bottom of `OnboardingView`, after the existing permission-check lines, add engine preparation and refresh:

```swift
            appState.refreshEngineReadiness()
            if appState.settings.transcriptionEngine == .apple
                && !appState.isEngineReady && !appState.isPreparingEngine {
                appState.prepareEngine()
            }
```

Add an `.onChange` to auto-prepare Apple when the user switches engines in onboarding (place after `.onAppear`):

```swift
        .onChange(of: appState.settings.transcriptionEngine) { _, newValue in
            appState.refreshEngineReadiness()
            if newValue == .apple && !appState.isEngineReady && !appState.isPreparingEngine {
                appState.prepareEngine()
            }
        }
```

(The `settings.onChange` closure in AppState already updates `pipeline.engineChoice` and auto-prepares Apple; this `.onChange` keeps the onboarding view's readiness in sync and is safe because `prepareEngine()` guards against double-prep.)

- [ ] **Step 3: Build to verify**

Run: `xcodebuild -project Dict-app.xcodeproj -scheme Dict-app -destination 'platform=macOS' build 2>&1 | tail -8`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add Dict-app/OnboardingWindow.swift
git commit -m "feat: onboarding engine picker with adaptive readiness"
```

---

### Task 8: Settings General tab engine picker

**Files:**
- Modify: `Dict-app/SettingsView.swift`

**Interfaces:**
- Consumes: `settings.transcriptionEngine` (Task 2), `AppState` readiness/`prepareEngine()` (Task 6). NOTE: `GeneralSettingsTab` currently takes only `settings`; it needs `appState` to show readiness and trigger downloads.

- [ ] **Step 1: Give GeneralSettingsTab access to AppState**

In `Dict-app/SettingsView.swift`, change `GeneralSettingsTab` to also take the app state. Change:

```swift
struct GeneralSettingsTab: View {
    @Bindable var settings: SettingsStore
    @State private var loginItem = LoginItemManager()
```

to:

```swift
struct GeneralSettingsTab: View {
    @Bindable var settings: SettingsStore
    var appState: AppState
    @State private var loginItem = LoginItemManager()
```

- [ ] **Step 2: Add the engine section**

Add a new `Section` to the `Form` in `GeneralSettingsTab.body`, after the hotkey/activation `Section` and before the formatting `Section`:

```swift
            Section {
                Picker("Transcription engine", selection: $settings.transcriptionEngine) {
                    ForEach(TranscriptionEngineChoice.allCases, id: \.self) { choice in
                        Text(choice.displayName).tag(choice)
                    }
                }
                Text(engineStatusCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if settings.transcriptionEngine == .whisper
                    && !appState.isEngineReady && !appState.isPreparingEngine {
                    Button("Download Whisper model (~1 GB)") { appState.prepareEngine() }
                        .controlSize(.small)
                }
                if appState.isPreparingEngine && settings.transcriptionEngine == .whisper {
                    ProgressView(value: appState.engineDownloadProgress)
                        .progressViewStyle(.linear)
                }
            }
```

Add this computed property to `GeneralSettingsTab`:

```swift
    private var engineStatusCaption: String {
        if appState.isPreparingEngine {
            return settings.transcriptionEngine == .whisper ? "Downloading…" : "Preparing…"
        }
        if appState.isEngineReady {
            return "\(settings.transcriptionEngine.displayName) is ready. \(settings.transcriptionEngine.blurb)"
        }
        return settings.transcriptionEngine.blurb
    }
```

- [ ] **Step 3: Update the call site in MainWindow**

In `Dict-app/MainWindow.swift`, the detail switch constructs `GeneralSettingsTab(settings: appState.settings)`. Change it to:

```swift
                GeneralSettingsTab(settings: appState.settings, appState: appState)
```

- [ ] **Step 4: Build to verify**

Run: `xcodebuild -project Dict-app.xcodeproj -scheme Dict-app -destination 'platform=macOS' build 2>&1 | tail -8`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Run the full test suite**

Run: `xcodebuild -project Dict-app.xcodeproj -scheme Dict-app -destination 'platform=macOS' test 2>&1 | tail -20`
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add Dict-app/SettingsView.swift Dict-app/MainWindow.swift
git commit -m "feat: engine picker in Settings General tab"
```

---

## Final verification (after all tasks)

- [ ] Full build: `xcodebuild ... build` → `** BUILD SUCCEEDED **`
- [ ] Full test suite: `xcodebuild ... test` → all green
- [ ] Manual smoke (user): fresh-install shows Apple default in onboarding, Apple prepares without a 1 GB download, dictation inserts text; switching to Whisper offers the download; the recording HUD shows Liquid Glass.
