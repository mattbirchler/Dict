# Transcription Engine Choice + Liquid Glass HUD — Design

**Date:** 2026-07-11
**App:** Dict (macOS 26.4 menu-bar dictation app, fully on-device)

This spec covers two independent features shipping together on one feature
branch:

- **Feature A — Liquid Glass HUD:** replace the recording HUD's flat blur with
  native macOS Tahoe Liquid Glass (real refraction).
- **Feature B — Transcription engine choice:** let users pick Apple's on-device
  `SpeechAnalyzer`/`SpeechTranscriber` as an alternative to WhisperKit, chosen
  at onboarding and switchable in Settings.

The two features touch mostly disjoint files. Feature A is a self-contained
view change; Feature B is an architectural addition behind a new protocol.

---

## Feature A — Liquid Glass HUD

### Goal
The recording HUD (`WaveformHUD`) currently uses
`.background(.ultraThinMaterial, in: Capsule())` — a flat blur. Replace it with
native Liquid Glass so the capsule refracts and reflects the content behind the
floating panel.

### Design
- In `WaveformHUD.body`, replace the `.background(.ultraThinMaterial, in: Capsule())`
  modifier with `.glassEffect(.regular, in: .capsule)`.
- `.glassEffect` is applied last, after the padding modifiers, per Apple's
  guidance ("apply `.glassEffect()` after other modifiers that affect
  appearance").
- Keep the existing layout unchanged: recording dot, 7-bar waveform, status
  label, and the same horizontal/vertical padding.
- Deployment target is macOS 26.4, so `glassEffect` is available
  unconditionally — no availability guard or material fallback.
- The HUD is hosted in a borderless, transparent `NSPanel`
  (`HUDPanelController`); the glass refracts the desktop/app content behind the
  panel. `panel.isOpaque = false` and `backgroundColor = .clear` are already
  set, which is what glass needs.

### Scope boundary (YAGNI)
No layout/proportion redesign, no tint/interactive variants, no morphing
transitions. Just the material swap. (User chose "tasteful glass swap".)

### Testing
Pure SwiftUI view change with no logic — verified by successful build and
manual visual check. No unit test.

---

## Feature B — Transcription engine choice

### Goal
Offer two on-device transcription engines and let the user choose:

- **WhisperKit** (current): more accurate, slower, requires a ~1 GB model
  download before first use.
- **Apple `SpeechAnalyzer`/`SpeechTranscriber`** (new): faster, already
  on-device (Apple-managed assets, no 1 GB download), potentially less
  accurate.

New installs default to **Apple** (lightest first run). Existing installs keep
**Whisper** (see Migration). English-only for both (matches current Whisper
path); a language picker is explicitly out of scope for this feature.

### Architecture

#### `TranscriptionEngine` protocol
A new protocol both engines conform to. `@MainActor`.

```swift
@MainActor
protocol TranscriptionEngine: AnyObject {
    /// Trailing rolling buffer of recent audio levels; the HUD reads `.last`
    /// (normalized ~0...1) to drive the waveform. Matches the shape the HUD
    /// already expects from WhisperKit's `relativeEnergy`.
    var audioEnergy: [Float] { get }

    var isRecording: Bool { get }

    /// True once the engine's model/assets are downloaded, installed, and
    /// loaded so recording can begin immediately.
    var isReady: Bool { get }

    /// True when this engine still needs a user-visible asset download before
    /// it is usable (Whisper before its model download). Apple reports false
    /// once assets are installed; asset install, if needed, is reported via
    /// `onProgress` during `prepare()`.
    var needsDownload: Bool { get }

    /// Download-progress callback (0...1) used during `prepare()`.
    var onProgress: ((Double) -> Void)? { get set }

    /// Idempotent: downloads/installs and loads whatever the engine needs.
    func prepare() async throws

    func start() async throws
    func cancel()
    func stop() async -> String
}
```

#### Engines
- **`StreamingTranscriptionService`** (existing, WhisperKit) is made to conform:
  - `ensureLoaded()` → satisfies `prepare()` (kept as the implementation).
  - `isModelLoaded` → exposed as `isReady`.
  - `needsDownload` returns `true` (Whisper always has a download step).
  - Already has `audioEnergy`, `isRecording`, `start`, `cancel`, `stop`,
    `onProgress`. Minimal changes.
- **`AppleSpeechTranscriptionService`** (new) conforms:
  - Owns its own `AVAudioEngine` with an input tap (WhisperKit's
    `AudioProcessor` is not involved for this engine).
  - `prepare()`: ensures the en-US `SpeechTranscriber` assets are installed
    (via the Speech framework asset-install API), reporting progress through
    `onProgress`; assets are frequently already present, in which case
    `prepare()` returns quickly and `needsDownload` is `false`.
  - `start()`: starts the `AVAudioEngine` tap and a `SpeechAnalyzer` streaming
    session; the tap feeds `AnalyzerInput` buffers into the analyzer and also
    computes per-buffer RMS energy appended to `audioEnergy` (rolling window).
  - `stop()`: finalizes the analyzer and returns the concatenated finalized
    transcript as a plain `String`.
  - `cancel()`: tears down the engine/analyzer and discards.
  - Returns clean text directly — it does **not** run the WhisperKit-specific
    VAD gate / `TranscriptFilter` (those operate on Whisper segments +
    per-frame voice activity). Downstream Apple-Intelligence formatting in
    `PipelineCoordinator` still applies.

  Exact `SpeechAnalyzer`/`SpeechTranscriber` API (construction, asset install,
  audio feeding, result reading, lifecycle, authorization) is captured in the
  implementation plan from verified Apple documentation.

#### `PipelineCoordinator`
- Holds both engines as `let`:
  `whisperEngine: StreamingTranscriptionService`,
  `appleEngine: AppleSpeechTranscriptionService`.
- Stores the current `engineChoice: TranscriptionEngineChoice` and exposes a
  computed `activeEngine: any TranscriptionEngine`.
- `startRecording` / `cancelRecording` / `stopRecordingAndProcess` route to
  `activeEngine`. The formatting + history + text-insertion tail is unchanged.

#### `SettingsStore`
- New enum:
  ```swift
  enum TranscriptionEngineChoice: String, CaseIterable {
      case apple, whisper
      var displayName: String { ... }   // "Apple", "Whisper"
      var blurb: String { ... }          // one-line tradeoff for onboarding
  }
  ```
- New property `transcriptionEngine: TranscriptionEngineChoice` with a `didSet`
  that writes UserDefaults and fires `onChange(.transcriptionEngine)`.
- Add `.transcriptionEngine` to the existing `Change` enum.

##### Migration
On first read when the UserDefaults key is absent:
- If `hasCompletedOnboarding == true` (an existing user upgrading) → default to
  `.whisper`, so their experience is unchanged and they aren't forced onto a
  different engine.
- Otherwise (fresh install) → default to `.apple`.

The chosen value is then persisted so the decision is stable.

#### `AppState`
- Mirrors the active engine's readiness into its own `@Observable` state so
  SwiftUI observes concrete `AppState` properties rather than a type-erased
  protocol existential:
  - `isEngineReady: Bool`
  - `engineNeedsDownload: Bool`
  - `isPreparingEngine: Bool` (replaces `isLoadingWhisper`)
  - `engineDownloadProgress: Double` (replaces `whisperDownloadProgress`)
- `preloadWhisperModel()` generalizes to `prepareEngine()`: calls
  `pipeline.activeEngine.prepare()`, mirrors `onProgress` → progress, sets
  ready/needsDownload on completion.
- Reacts to `settings.onChange(.transcriptionEngine)`: updates
  `pipeline.engineChoice`, resets mirrored readiness, and calls
  `prepareEngine()` for the newly selected engine.
- The `guard ... !isLoadingWhisper` in `startRecording` becomes
  `!isPreparingEngine`.

### UI

#### Onboarding (`OnboardingView`)
- Add a segmented `Picker` bound to `settings.transcriptionEngine` with the two
  choices and their one-line blurbs (accuracy vs. speed / download vs.
  on-device).
- Replace the Whisper-specific "Whisper Model" download row with an **adaptive
  readiness row** driven by the active engine:
  - **Whisper selected:** "Speech model — Download (~1 GB)" with the existing
    progress UI; "Ready" when loaded.
  - **Apple selected:** "Apple speech — Ready" (or a brief "Preparing…" while
    assets install the first time). No 1 GB download.
- Changing the engine picker triggers `appState.prepareEngine()` for the newly
  selected engine.
- "Get Started" is enabled when `appState.isEngineReady` for the active engine
  (replacing the direct `transcriptionService.isModelLoaded` check).
- The Speech Recognition permission row stays — it is genuinely required by the
  Apple engine.

#### Settings (`GeneralSettingsTab`)
- Add a `Picker("Transcription engine", selection: $settings.transcriptionEngine)`
  with the two choices, plus a caption describing the tradeoff and the current
  engine's readiness (e.g. "Downloading… / Ready"), with a Download/Prepare
  button when the selected engine isn't ready.

### Permissions / Info.plist
- Apple's `SpeechTranscriber` requires Speech Recognition authorization and a
  usage-description key; the exact key and authorization call are pinned in the
  implementation plan from Apple docs. The onboarding Speech Recognition row and
  `PermissionChecker` support already exist.
- Microphone permission and the audio-input entitlement already exist.
- Fully on-device; no network beyond the one-time asset download each engine
  performs.

### Testing
- **`SettingsStoreTests`:** default is `.apple` on a fresh store; migration
  yields `.whisper` when `hasCompletedOnboarding` is pre-set; round-trip
  persistence; `onChange(.transcriptionEngine)` fires.
- **Pipeline selection:** a fake `TranscriptionEngine` (records
  prepare/start/stop calls, returns canned text) injected to verify
  `PipelineCoordinator` routes to the engine matching `engineChoice` and that
  switching `engineChoice` changes `activeEngine`.
- **Apple engine unit-testable pieces:** RMS-energy normalization (buffer →
  `audioEnergy` value in expected range) and finalized-result text assembly
  (result stream → concatenated string), tested with injected inputs rather
  than live audio.
- **Out of the required suite (documented limitation):** Apple end-to-end
  transcription from real audio depends on installed OS assets and microphone
  hardware, so it is not a deterministic unit test. WhisperKit's existing
  `EndToEndTranscriptionTests` remain unchanged.

### Files

**Feature A**
- Modify: `Dict-app/WaveformHUD.swift`

**Feature B**
- Create: `Dict-app/TranscriptionEngine.swift` (protocol)
- Create: `Dict-app/AppleSpeechTranscriptionService.swift`
- Modify: `Dict-app/StreamingTranscriptionService.swift` (conform to protocol)
- Modify: `Dict-app/PipelineCoordinator.swift` (two engines + active selection)
- Modify: `Dict-app/SettingsStore.swift` (engine enum, property, migration, Change case)
- Modify: `Dict-app/AppState.swift` (mirrored readiness, `prepareEngine`, engine-switch handling)
- Modify: `Dict-app/OnboardingWindow.swift` (engine picker + adaptive readiness row)
- Modify: `Dict-app/SettingsView.swift` (engine picker in General tab)
- Modify: `Dict-app/Dict_appApp.swift` (call sites: `prepareEngine` etc.)
- Modify: `Info.plist` / project settings (Speech Recognition usage description, if not already present)
- Tests: `Dict-appTests/SettingsStoreTests.swift`, plus new pipeline-selection
  and Apple-engine-unit tests.

### Global constraints
- Deployment target macOS 26.4; Swift/SwiftUI/AppKit; fully on-device (no
  servers).
- New `.swift` files under `Dict-app/` and `Dict-appTests/` are auto-included
  via `PBXFileSystemSynchronizedRootGroup` — do **not** edit `project.pbxproj`
  to add files.
- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`) — not XCTest.
- Version-bump commits (if any) use `<marketingVersion> build <buildNumber>`.
