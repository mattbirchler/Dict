# Phase 1: Ship-Ready Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Take Dict from a personal build to something a stranger can download, install, trust, and update, by closing the eleven blockers (B1-B11) in the audit.

**Architecture:** Dict is a menu-bar-only SwiftUI/AppKit macOS app. `AppDelegate` wires `AppState` (observable state), `PipelineCoordinator` (engine, formatter, insertion, history), `KeyMonitor` (CGEvent tap), `HUDPanelController` (floating NSPanel), and `MenuBarManager`. Two engines stay after this phase: `AppleSpeechTranscriptionService` and `ParakeetTranscriptionService`, both behind the `TranscriptionEngine` protocol. Release tooling follows the pattern already used by the Bench project (`Makefile` + `scripts/notarize.sh` + `scripts/publish.sh` + `scripts/appcast.py`), adapted to this repo hosting its own releases and feed.

**Tech Stack:** Swift 6, SwiftUI, AppKit, CoreAudio HAL, os.log/OSLogStore, Swift Testing (`@Test`, `#expect`), Sparkle 2.9.1 (SPM), FluidAudio, xcodebuild + notarytool + gh.

**Spec:** `docs/audit-2026-11-02.md` (sections 2, 6, and 8; decisions: keep the name Dict, make the repo public, delete Whisper, Apple-first default engine).

## Global Constraints

- No em dashes in any user-facing text (UI copy, docs, release notes, alerts).
- Fully on-device: no new network calls except model download and the Sparkle feed.
- No paid services. GitHub Releases host the zip; `appcast.xml` stays at `https://raw.githubusercontent.com/mattbirchler/Dict-app/main/appcast.xml` (already in `INFOPLIST_KEY_SUFeedURL`).
- Deployment target `MACOSX_DEPLOYMENT_TARGET = 26.0` in every configuration (raise only if the build proves an API needs more, and record which).
- Version commits are named `<marketingVersion> build <buildNumber>` (for example `1.0 build 5`).
- The Xcode project uses file-system-synchronized groups: adding or deleting a `.swift` file on disk adds or removes it from the target. Do not edit `project.pbxproj` for file membership.
- Tests use Swift Testing. Run a suite with:
  `xcodebuild test -scheme Dict-app -destination 'platform=macOS' -only-testing:Dict-appTests/<SuiteName> 2>&1 | grep -E "✔|✘|error:|TEST (SUCCEEDED|FAILED)" | tail -20`
  Build with: `xcodebuild -scheme Dict-app -configuration Debug -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"`
- One commit per task, written in the imperative with a conventional prefix (`feat:`, `fix:`, `chore:`, `docs:`, `refactor:`).

## Review Focus

Inputs the spec implies but no existing test exercises. Each line's test is added to the task that owns the code.

1. A user upgrading from a build whose stored engine is `whisper` must land on `apple` and never crash on the unknown raw value. (Task 1)
2. The hotkey pressed while the engine is still loading must show a notice and must not leave the HUD stuck in "Processing" when the key is released. (Task 4)
3. A system default input that is a Bluetooth headset must resolve to the built-in microphone under the Automatic choice, and a saved device that is unplugged must fall back rather than fail to record. (Task 7)
4. A Debug build, or any build already inside `/Applications` or `~/Applications`, must never be offered the move. (Task 8)
5. `publish.sh` must refuse to run with uncommitted changes, from a branch other than `main`, or without release notes, so a half-published feed can't happen. (Task 10, verified by dry run)

---

### Task 1: Delete the Whisper path (B9)

**Files:**
- Delete: `Dict-app/StreamingTranscriptionService.swift`, `Dict-app/SpeechSegmenter.swift`, `Dict-app/ChunkDecodeQueue.swift`, `Dict-app/TranscriptAssembler.swift`, `Dict-app/VoiceGate.swift`, `Dict-app/TranscriptFilter.swift`
- Delete: `Dict-appTests/EndToEndTranscriptionTests.swift`, `Dict-appTests/StreamingEquivalenceTests.swift`, `Dict-appTests/SpeechSegmenterTests.swift`, `Dict-appTests/ChunkDecodeQueueTests.swift`, `Dict-appTests/TranscriptAssemblerTests.swift`, `Dict-appTests/VoiceGateTests.swift`, `Dict-appTests/TranscriptFilterTests.swift`
- Create: `Dict-app/AudioInputDevices.swift` (holds the default-input-name lookup that `Dict_appApp.swift:71` reads from the deleted service; Task 7 grows it)
- Modify: `Dict-app/SettingsStore.swift` (remove `.whisper`, migration), `Dict-app/PipelineCoordinator.swift` (remove `whisperEngine`), `Dict-app/AppState.swift:canAutoPrepare`, `Dict-app/TranscriptionEngine.swift` doc comment, `Dict-app/SettingsView.swift:169` ("Built with FluidAudio and Sparkle."), `Dict-app/Dict_appApp.swift:71`
- Modify: `Dict-app.xcodeproj/project.pbxproj` (remove the WhisperKit package reference and product; this is a package edit, not file membership), `Dict-app.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
- Test: `Dict-appTests/SettingsStoreTests.swift`, `Dict-appTests/PipelineEngineSelectionTests.swift`, `Dict-appTests/ParakeetEndToEndTests.swift`

**Interfaces:**
- Produces: `enum TranscriptionEngineChoice: String, CaseIterable { case apple, parakeet }`
- Produces: `enum AudioInputDevices { static var defaultInputDeviceName: String }` (moved verbatim from `StreamingTranscriptionService.inputDeviceName`)
- Produces: `PipelineCoordinator.shouldFormat(enabled:engine:context:)` unchanged in signature; with Whisper gone it returns `enabled && (engine == .apple || context == .coding)`.

- [ ] **Step 1: Rewrite the Whisper tests in `SettingsStoreTests.swift`**

Replace `existingUserMigratesToWhisper` and the two tests that store `.whisper` with:

```swift
@Test func storedWhisperMigratesToApple() {
    let defaults = makeDefaults()
    defaults.set("whisper", forKey: "transcriptionEngine")
    defaults.set(true, forKey: "hasCompletedOnboarding")
    let store = SettingsStore(defaults: defaults)
    #expect(store.transcriptionEngine == .apple)
}

@Test func existingUserWithoutEngineKeyGetsApple() {
    let defaults = makeDefaults()
    defaults.set(true, forKey: "hasCompletedOnboarding")
    #expect(SettingsStore(defaults: defaults).transcriptionEngine == .apple)
}
```

(`makeDefaults()` is whatever helper the file already uses to build an isolated `UserDefaults`; keep it.) In `PipelineEngineSelectionTests.swift` delete the `.whisper` selection test and change the `shouldFormat` expectations to: apple+general → true, parakeet+general → false, parakeet+coding → true, apple+coding → true, disabled → false for every engine.

- [ ] **Step 2: Run the two suites to verify they fail to compile**

Run: the test command for `SettingsStoreTests` and `PipelineEngineSelectionTests`.
Expected: build error, `.whisper` still exists and `makeDefaults` expectations don't match.

- [ ] **Step 3: Delete the thirteen Whisper files listed above**

`git rm` each. Then in `ParakeetEndToEndTests.swift` remove `import WhisperKit` and replace the `TranscriptFilter.normalize(text)` call with a private helper in that file:

```swift
private func normalize(_ text: String) -> String {
    text.lowercased()
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
}
```

- [ ] **Step 4: Create `AudioInputDevices.swift` and point the HUD at it**

Move the body of `StreamingTranscriptionService.inputDeviceName` (CoreAudio default-input lookup) into `enum AudioInputDevices { static var defaultInputDeviceName: String }`. In `Dict_appApp.swift` change `micName: { StreamingTranscriptionService.inputDeviceName }` to `micName: { AudioInputDevices.defaultInputDeviceName }`.

- [ ] **Step 5: Remove `.whisper` everywhere**

`SettingsStore.swift`: drop the case, its `displayName`/`blurb`/`modelDisplayName`/`downloadPrompt` arms, and the `hasCompletedOnboarding ? .whisper : .apple` branch; the init becomes `TranscriptionEngineChoice(rawValue:) ?? .apple`. `PipelineCoordinator.swift`: delete `whisperEngine` and the `.whisper` arms. `AppState.canAutoPrepare`: delete the `.whisper` arm. `SettingsView.swift`: the About credit line becomes `"Built with FluidAudio and Sparkle."`

- [ ] **Step 6: Remove the WhisperKit package**

In `project.pbxproj` delete the four WhisperKit entries (the `PBXBuildFile`, the `Frameworks` build-phase line, the `packageProductDependencies` line, the `XCRemoteSwiftPackageReference "WhisperKit"` block and its entry in `packageReferences`, and the `XCSwiftPackageProductDependency` block). Then run `xcodebuild -resolvePackageDependencies -scheme Dict-app` so `Package.resolved` drops whisperkit and its transitive pins (swift-transformers, swift-jinja, yyjson, swift-argument-parser, swift-collections, swift-asn1, swift-crypto; keep any that FluidAudio or Sparkle still pull in, which the resolve decides).

- [ ] **Step 7: Build and run the three touched suites**

Run: the build command, then the test command for `SettingsStoreTests`, `PipelineEngineSelectionTests`, and `ParakeetEndToEndTests`.
Expected: BUILD SUCCEEDED, every test passes.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "refactor: remove the Whisper engine and WhisperKit"
```

---

### Task 2: Deployment target and version cleanup (B5)

**Files:**
- Modify: `Dict-app.xcodeproj/project.pbxproj` lines 278, 336, 428, 448 (`MACOSX_DEPLOYMENT_TARGET`), 352, 390, 425, 445 (`CURRENT_PROJECT_VERSION`), 369, 407, 429, 449 (`MARKETING_VERSION`)

- [ ] **Step 1: Set every `MACOSX_DEPLOYMENT_TARGET` to `26.0`, every `CURRENT_PROJECT_VERSION` to `1`, every `MARKETING_VERSION` to `1.0`**

Use `sed -i ''` on the four lines of each kind. The test target's values follow the app target.

- [ ] **Step 2: Build**

Run: the build command.
Expected: BUILD SUCCEEDED. If an availability error names an API newer than 26.0, raise the target to exactly the version the error names and note it in the commit body.

- [ ] **Step 3: Commit**

```bash
git add Dict-app.xcodeproj/project.pbxproj
git commit -m "chore: target macOS 26.0 and set version 1.0 build 1 in every configuration"
```

---

### Task 3: Real logging plus Copy diagnostic log (B8)

**Files:**
- Create: `Dict-app/Log.swift`, `Dict-app/DiagnosticLog.swift`
- Modify: every file with `print(` (64 call sites across `AppState`, `PipelineCoordinator`, `ParakeetTranscriptionService`, `AppleSpeechTranscriptionService`, `TranscriptFormatter`, `PermissionChecker`, `OnboardingWindow`, `KeyMonitor`, `TextInsertionService`, `HistoryStore`), `Dict-app/SettingsView.swift` (About tab)
- Test: `Dict-appTests/DiagnosticLogTests.swift`

**Interfaces:**
- Produces: `enum Log { static let subsystem = "birchtree.Dict-app"; static let app, pipeline, engine, formatter, keys, insertion, permissions, hud, updates: Logger }` (one `Logger(subsystem:category:)` per name).
- Produces: `enum DiagnosticLog { static func recent(since interval: TimeInterval = 3600, now: Date = .now) throws -> String; static func format(_ entries: [(date: Date, category: String, level: String, message: String)]) -> String }`. `recent` reads `OSLogStore(scope: .currentProcessIdentifier)`, filters `subsystem == Log.subsystem`, and returns one line per entry: `HH:mm:ss.SSS [category] level: message`, oldest first, prefixed by a header line `Dict <version> (<build>) on macOS <version>`.

- [ ] **Step 1: Write the failing test**

```swift
@Test func formatsEntriesOldestFirstWithHeader() {
    let t0 = Date(timeIntervalSince1970: 0)
    let out = DiagnosticLog.format([
        (date: t0.addingTimeInterval(1), category: "pipeline", level: "info", message: "second"),
        (date: t0, category: "engine", level: "error", message: "first"),
    ])
    let lines = out.split(separator: "\n")
    #expect(lines[0].hasPrefix("Dict "))
    #expect(lines[1].contains("[engine] error: first"))
    #expect(lines[2].contains("[pipeline] info: second"))
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: test command for `DiagnosticLogTests`. Expected: compile error, `DiagnosticLog` undefined.

- [ ] **Step 3: Implement `Log.swift` and `DiagnosticLog.swift`**

`format` sorts by date and uses a `DateFormatter` with `HH:mm:ss.SSS`. `recent` maps `OSLogEntryLog` entries to the tuple (level from `entry.level`: debug/info/notice/error/fault) and calls `format`.

- [ ] **Step 4: Replace every `print(` with the matching `Log.<category>` call**

Levels: errors and failures → `.error`, cancellations and state changes → `.info`, timing lines → `.debug`. Interpolated user text (transcripts, pasted strings) gets `privacy: .private`; everything else `privacy: .public`. Verify with `grep -c "print(" Dict-app/*.swift` → 0.

- [ ] **Step 5: Add "Copy Diagnostic Log" to the About tab**

In `AboutSettingsTab`, under "Check for Updates…", a `Button("Copy Diagnostic Log")` that calls `DiagnosticLog.recent()`, puts the result on `NSPasteboard.general`, and shows `Text("Copied. Paste it into a bug report.")` in `.caption` for 3 seconds (`@State private var copiedAt: Date?`). On a thrown error the caption reads `"Couldn't read the log: <error.localizedDescription>"`.

- [ ] **Step 6: Build, run `DiagnosticLogTests`, and confirm the log shows up**

Run: build, test. Then launch the Debug app, dictate once, and run `log show --last 2m --predicate 'subsystem == "birchtree.Dict-app"' | tail -5`. Expected: pipeline lines appear.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: structured logging with a Copy Diagnostic Log button"
```

---

### Task 4: HUD error states (B4)

**Files:**
- Create: `Dict-app/DictationResult.swift`
- Modify: `Dict-app/PipelineCoordinator.swift:stopRecordingAndProcess`, `Dict-app/AppState.swift` (`onProcessingComplete`, `stopRecording`, `cancelProcessing`, `startRecording`), `Dict-app/HUDPanelController.swift` (`finish`, new `showNotice`), `Dict-app/WaveformHUD.swift` (`HUDMode.failed`), `Dict-app/Dict_appApp.swift` (wiring)
- Test: `Dict-appTests/DictationResultTests.swift`, `Dict-appTests/PipelineEngineSelectionTests.swift` (existing suite, add one)

**Interfaces:**
- Produces: `enum DictationResult: Equatable { case inserted(String), nothingHeard, failed }` with `var hudMessage: String? { inserted → nil, nothingHeard → "Nothing heard", failed → "Couldn't transcribe. Try again." }`.
- Produces: `PipelineCoordinator.stopRecordingAndProcess() async -> DictationResult` (returns `.nothingHeard` when the engine's text is empty, `.failed` when the task was cancelled or the engine threw, `.inserted(text)` otherwise).
- Produces: `AppState.onProcessingComplete: ((DictationResult) -> Void)?`; `AppState.canStartRecording: Bool` (`isEnabled && !isRecording && !isProcessing && isEngineReady`); `AppState.startBlockedReason: String?` (`"Loading speech model…"` while `isPreparingEngine`, `"Speech model isn't ready"` when not ready, nil otherwise).
- Produces: `HUDPanelController.finish(result: DictationResult)` (checkmark hold for `.inserted`; for the others morph to `.failed(message)` and hold 1.4 s); `HUDPanelController.showNotice(_ message: String)` (presents the HUD already in `.failed(message)`, holds 1.4 s, dismisses).
- Produces: `HUDMode.failed(message: String)`; `HUDMode` becomes `Equatable` by synthesis.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func hudMessages() {
    #expect(DictationResult.inserted("hi").hudMessage == nil)
    #expect(DictationResult.nothingHeard.hudMessage == "Nothing heard")
    #expect(DictationResult.failed.hudMessage == "Couldn't transcribe. Try again.")
}

@MainActor @Test func startIsBlockedWhileEnginePrepares() {
    let state = AppState(settings: SettingsStore(defaults: makeDefaults()))
    state.isPreparingEngine = true
    #expect(state.canStartRecording == false)
    #expect(state.startBlockedReason == "Loading speech model…")
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: test command for `DictationResultTests`. Expected: compile errors.

- [ ] **Step 3: Implement `DictationResult`, change the pipeline and AppState signatures, add `HUDMode.failed`**

`WaveformHUD`: in `.failed`, the header shows `Image(systemName: "exclamationmark.circle.fill")` in `.orange` where the checkmark goes, no level bars, and `statusText` returns the message. `isRecording` and `isExpanded` logic unchanged.

- [ ] **Step 4: Wire the notice in `AppDelegate`**

`keyMonitor.onRecordingStart`: if `!appState.canStartRecording`, call `hudController.showNotice(appState.startBlockedReason ?? "Can't start dictation")` and return without starting. `keyMonitor.onRecordingStop`: only call `showProcessing()` when `appState.isRecording` is true (so a blocked start followed by key-up doesn't strand a processing pill). `appState.onProcessingComplete = { hudController.finish(result: $0) }`.

- [ ] **Step 5: Build, test, and try it**

Run: build, `DictationResultTests`, `PipelineEngineSelectionTests`. Then launch and: (a) tap the hotkey for 300 ms in silence → "Nothing heard" pill; (b) switch to Parakeet with the model deleted from `~/Library/Application Support/FluidAudio` and press the hotkey → "Loading speech model…" notice, no stuck pill on release.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: HUD shows nothing-heard, failure, and engine-loading states"
```

---

### Task 5: HUD on the active screen (B10)

**Files:**
- Create: `Dict-app/HUDScreenPicker.swift`
- Modify: `Dict-app/HUDPanelController.swift:position`
- Test: `Dict-appTests/HUDScreenPickerTests.swift`

**Interfaces:**
- Produces: `enum HUDScreenPicker { static func pick(screens: [CGRect], focusedWindow: CGRect?, mouse: CGPoint) -> Int? }`: the index of the screen containing the focused window's center, else the screen containing the mouse, else 0 when screens is non-empty, else nil.
- Produces: `HUDScreenPicker.focusedWindowFrame() -> CGRect?` reading `kAXFocusedWindowAttribute` of the frontmost app's `AXUIElementCreateApplication(pid)` with a 0.25 s messaging timeout, converting AX top-left coordinates to AppKit bottom-left using the primary screen's height.

- [ ] **Step 1: Write the failing tests**

```swift
let left = CGRect(x: 0, y: 0, width: 1000, height: 800)
let right = CGRect(x: 1000, y: 0, width: 1000, height: 800)

@Test func prefersFocusedWindowScreen() {
    #expect(HUDScreenPicker.pick(screens: [left, right], focusedWindow: CGRect(x: 1200, y: 100, width: 400, height: 300), mouse: CGPoint(x: 10, y: 10)) == 1)
}
@Test func fallsBackToMouse() {
    #expect(HUDScreenPicker.pick(screens: [left, right], focusedWindow: nil, mouse: CGPoint(x: 1500, y: 10)) == 1)
}
@Test func fallsBackToFirstScreen() {
    #expect(HUDScreenPicker.pick(screens: [left, right], focusedWindow: nil, mouse: CGPoint(x: -50, y: -50)) == 0)
    #expect(HUDScreenPicker.pick(screens: [], focusedWindow: nil, mouse: .zero) == nil)
}
```

- [ ] **Step 2: Run to verify failure.** Expected: compile error.

- [ ] **Step 3: Implement `HUDScreenPicker` and use it in `position(_:)`**

`position` builds `screens = NSScreen.screens.map(\.frame)`, calls `pick`, and uses that screen's `visibleFrame` instead of `NSScreen.main`.

- [ ] **Step 4: Build, run `HUDScreenPickerTests`, and try it with a second display** (or skip the manual check if only one display is attached and say so in the commit body).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: show the HUD on the screen you're typing on"
```

---

### Task 6: Only ask for permissions the engine needs (B6)

**Files:**
- Modify: `Dict-app/SettingsStore.swift` (`TranscriptionEngineChoice.needsSpeechRecognitionPermission`), `Dict-app/PermissionChecker.swift` (`requiredGranted(for:)`), `Dict-app/OnboardingWindow.swift` (conditional row, gate), `Dict-app/MenuBarManager.swift:menuNeedsUpdate` ("Fix Permissions…" condition)
- Test: `Dict-appTests/PermissionCheckerTests.swift`

**Interfaces:**
- Produces: `TranscriptionEngineChoice.needsSpeechRecognitionPermission: Bool` (apple → true, parakeet → false).
- Produces: `PermissionChecker.requiredGranted(for engine: TranscriptionEngineChoice) -> Bool` (`microphoneGranted && accessibilityGranted && (!engine.needsSpeechRecognitionPermission || speechRecognitionGranted)`). `allGranted` is removed.

- [ ] **Step 1: Write the failing test**

```swift
@Test func parakeetDoesNotNeedSpeechRecognition() {
    let checker = PermissionChecker()
    checker.microphoneGranted = true
    checker.accessibilityGranted = true
    checker.speechRecognitionGranted = false
    #expect(checker.requiredGranted(for: .parakeet))
    #expect(!checker.requiredGranted(for: .apple))
}
```

- [ ] **Step 2: Run to verify failure.** Expected: compile error.

- [ ] **Step 3: Implement, then update the UI**

Onboarding: wrap the Speech Recognition `PermissionRow` in `if appState.settings.transcriptionEngine.needsSpeechRecognitionPermission`; the "Grant all permissions…" caption and the menu's "Fix Permissions…" use `requiredGranted(for: appState.settings.transcriptionEngine)`.

- [ ] **Step 4: Build and run `PermissionCheckerTests`.** Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: ask for Speech Recognition only when the Apple engine needs it"
```

---

### Task 7: Microphone picker (B11)

**Files:**
- Modify: `Dict-app/AudioInputDevices.swift` (from Task 1), `Dict-app/SettingsStore.swift` (new `inputDevice` setting + `Change.inputDevice`), `Dict-app/AppState.swift` (forward the choice to the pipeline), `Dict-app/PipelineCoordinator.swift` (`inputDeviceChoice`, apply before `start()`), `Dict-app/ParakeetTranscriptionService.swift` and `Dict-app/AppleSpeechTranscriptionService.swift` (`var inputDeviceID: AudioDeviceID?` applied in `start()` before the tap is installed), `Dict-app/SettingsView.swift` (picker), `Dict-app/Dict_appApp.swift` (HUD `micName` shows the resolved device)
- Create: `Dict-app/InputDeviceSelection.swift`
- Test: `Dict-appTests/InputDeviceSelectionTests.swift`, `Dict-appTests/SettingsStoreTests.swift` (round-trip)

**Interfaces:**
- Produces: `struct AudioInputDevice: Identifiable, Equatable { let id: AudioDeviceID; let uid: String; let name: String; let transport: Transport; enum Transport { case builtIn, bluetooth, usb, other } }`
- Produces: `AudioInputDevices.all() -> [AudioInputDevice]` (devices with at least one input stream, via `kAudioHardwarePropertyDevices` and `kAudioDevicePropertyStreams` on the input scope; transport from `kAudioDevicePropertyTransportType`, mapping `kAudioDeviceTransportTypeBuiltIn`, `kAudioDeviceTransportTypeBluetooth`/`BluetoothLE`, `kAudioDeviceTransportTypeUSB`); `AudioInputDevices.systemDefault() -> AudioInputDevice?`; `AudioInputDevices.apply(_ id: AudioDeviceID, to engine: AVAudioEngine) throws` (sets `kAudioOutputUnitProperty_CurrentDevice` on `engine.inputNode.audioUnit`, must run before `engine.start()`).
- Produces: `enum InputDeviceChoice: Equatable, Codable { case automatic, systemDefault, device(uid: String) }` stored in `SettingsStore.inputDevice` under key `"inputDevice"` as JSON, default `.automatic`; `displayName`: "Automatic", "System default", or the device name.
- Produces: `enum InputDeviceSelection { static func resolve(_ choice: InputDeviceChoice, devices: [AudioInputDevice], systemDefault: AudioInputDevice?) -> AudioInputDevice? }`. Rules: `.systemDefault` → systemDefault. `.device(uid)` → the matching device, else fall through to `.automatic`. `.automatic` → systemDefault unless its transport is `.bluetooth` and a `.builtIn` device exists, in which case the built-in one; nil when there are no devices.
- Produces: `PipelineCoordinator.inputDeviceChoice: InputDeviceChoice` and `PipelineCoordinator.resolvedInputDevice() -> AudioInputDevice?` (used by both `startRecording()` and the HUD's `micName`).

- [ ] **Step 1: Write the failing tests**

```swift
let builtIn = AudioInputDevice(id: 1, uid: "built", name: "MacBook Pro Microphone", transport: .builtIn)
let airpods = AudioInputDevice(id: 2, uid: "air", name: "AirPods Pro", transport: .bluetooth)
let usb = AudioInputDevice(id: 3, uid: "usb", name: "Yeti", transport: .usb)

@Test func automaticSkipsBluetoothDefault() {
    #expect(InputDeviceSelection.resolve(.automatic, devices: [builtIn, airpods], systemDefault: airpods) == builtIn)
}
@Test func automaticKeepsUSBDefault() {
    #expect(InputDeviceSelection.resolve(.automatic, devices: [builtIn, usb], systemDefault: usb) == usb)
}
@Test func unpluggedSavedDeviceFallsBackToAutomatic() {
    #expect(InputDeviceSelection.resolve(.device(uid: "usb"), devices: [builtIn, airpods], systemDefault: airpods) == builtIn)
}
@Test func systemDefaultIsHonoredEvenWhenBluetooth() {
    #expect(InputDeviceSelection.resolve(.systemDefault, devices: [builtIn, airpods], systemDefault: airpods) == airpods)
}
@Test func noDevicesGivesNil() {
    #expect(InputDeviceSelection.resolve(.automatic, devices: [], systemDefault: nil) == nil)
}
```

Plus in `SettingsStoreTests`: `inputDeviceRoundTrips` sets `.device(uid: "usb")`, reloads the store from the same defaults, expects equality; and a fresh store expects `.automatic`.

- [ ] **Step 2: Run to verify failure.** Expected: compile errors.

- [ ] **Step 3: Implement `InputDeviceSelection`, `AudioInputDevice`, `AudioInputDevices.all/systemDefault/apply`, the setting, and the engine hook**

Both engines: in `start()`, right after the `targetFormat` guard and before `installTap`, `if let inputDeviceID { try AudioInputDevices.apply(inputDeviceID, to: audioEngine) }`. `PipelineCoordinator.startRecording()` sets `engine.inputDeviceID = resolvedInputDevice()?.id` before `engine.start()`. Note `warmUpAudio()` touches `inputNode` ahead of time; applying the device property after that is fine as long as the engine isn't running.

- [ ] **Step 4: Settings picker**

In `GeneralSettingsTab`, a new `Section` above the engine section: `Picker("Microphone", selection: $settings.inputDevice)` with tags `.automatic`, `.systemDefault`, then one `.device(uid:)` per `AudioInputDevices.all()` (refreshed `onAppear`), and a caption: `"Automatic uses your system microphone, but switches to the built-in one when a Bluetooth headset is the default. Bluetooth headsets record at low quality and take over audio output."`

- [ ] **Step 5: Build, run `InputDeviceSelectionTests` and `SettingsStoreTests`, and try it**

Dictate with Automatic while AirPods are connected and confirm the HUD names the built-in mic and the output doesn't switch.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: microphone picker with an Automatic mode that avoids Bluetooth input"
```

---

### Task 8: Move to /Applications on first launch (B3)

**Files:**
- Create: `Dict-app/ApplicationsMover.swift`
- Modify: `Dict-app/Dict_appApp.swift:applicationDidFinishLaunching` (first statement)
- Test: `Dict-appTests/ApplicationsMoverTests.swift`

**Interfaces:**
- Produces: `enum ApplicationsMover { static func shouldOffer(bundlePath: String, isDebugBuild: Bool, homeDirectory: String) -> Bool; @MainActor static func offerIfNeeded() }`. `shouldOffer` is false for Debug builds, for paths under `/Applications/`, `<home>/Applications/`, or any path containing `/DerivedData/`; true otherwise.
- `offerIfNeeded`: if `shouldOffer` (with `#if DEBUG` for `isDebugBuild`), show an `NSAlert` titled `"Move Dict to the Applications folder?"`, informative text `"Dict needs to stay in one place so macOS can remember its Accessibility permission and install updates."`, buttons `"Move to Applications"` and `"Not Now"`. On move: copy the bundle to `/Applications/Dict.app` with `FileManager.copyItem` (replace an existing one after confirming it isn't running by bundle ID), trash the original when its volume is writable, then `NSWorkspace.shared.openApplication(at:configuration:)` with `createsNewApplicationInstance = true` and `NSApp.terminate(nil)` in the completion handler. Copy failure shows a second alert `"Couldn't move Dict: <error>"` and continues launching.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func offersWhenRunningFromDownloads() {
    #expect(ApplicationsMover.shouldOffer(bundlePath: "/Users/m/Downloads/Dict.app", isDebugBuild: false, homeDirectory: "/Users/m"))
}
@Test func offersWhenRunningFromDiskImage() {
    #expect(ApplicationsMover.shouldOffer(bundlePath: "/Volumes/Dict/Dict.app", isDebugBuild: false, homeDirectory: "/Users/m"))
}
@Test func neverOffersForDebugOrInstalledOrDerivedData() {
    #expect(!ApplicationsMover.shouldOffer(bundlePath: "/Users/m/Downloads/Dict.app", isDebugBuild: true, homeDirectory: "/Users/m"))
    #expect(!ApplicationsMover.shouldOffer(bundlePath: "/Applications/Dict.app", isDebugBuild: false, homeDirectory: "/Users/m"))
    #expect(!ApplicationsMover.shouldOffer(bundlePath: "/Users/m/Applications/Dict.app", isDebugBuild: false, homeDirectory: "/Users/m"))
    #expect(!ApplicationsMover.shouldOffer(bundlePath: "/Users/m/Library/Developer/Xcode/DerivedData/x/Build/Products/Release/Dict.app", isDebugBuild: false, homeDirectory: "/Users/m"))
}
```

- [ ] **Step 2: Run to verify failure.** Expected: compile error.

- [ ] **Step 3: Implement `ApplicationsMover` and call `ApplicationsMover.offerIfNeeded()` as the first line of `applicationDidFinishLaunching`**

- [ ] **Step 4: Build, run `ApplicationsMoverTests`, and try a Release build from `~/Downloads`**

`xcodebuild -scheme Dict-app -configuration Release -derivedDataPath build build`, copy `build/Build/Products/Release/Dict-app.app` to `~/Downloads/`, open it. Expected: the alert, then the app relaunches from `/Applications`.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: offer to move Dict to the Applications folder on first launch"
```

---

### Task 9: Sparkle signing key (B1)

**Files:**
- Create: `scripts/sparkle-tools.sh`
- Modify: `Dict-app.xcodeproj/project.pbxproj` (add `INFOPLIST_KEY_SUPublicEDKey` next to `INFOPLIST_KEY_SUFeedURL` in both app configurations), `.gitignore` (add `vendor/`, `build/`, `fastlane/.env`, `fastlane/report.xml`)

**Interfaces:**
- Produces: `vendor/sparkle/bin/{generate_keys,sign_update,generate_appcast}` at the version in `Package.resolved` (2.9.1), fetched by `scripts/sparkle-tools.sh` (copy Bench's script, set `SPARKLE_VERSION=2.9.1`, make it executable).
- Produces: a keychain item for account `dict` (so it never collides with the existing default `ed25519` item or Bench's `bench`).

- [ ] **Step 1: Create `scripts/sparkle-tools.sh` and run it.** Expected: `vendor/sparkle/bin/sign_update` exists.

- [ ] **Step 2: Generate the key**

Run: `vendor/sparkle/bin/generate_keys --account dict`. Expected: prints a public key. If it reports a key already exists for that account, use `generate_keys --account dict -p` to print the existing public key instead.

- [ ] **Step 3: Add `INFOPLIST_KEY_SUPublicEDKey = "<public key>";` to both app configurations in `project.pbxproj`**, update `.gitignore`, and build.

- [ ] **Step 4: Tell Matt to back the private key up now**

Print the command for him to run himself: `vendor/sparkle/bin/generate_keys --account dict -x ~/Desktop/dict-sparkle-private-key.txt`, then store it in 1Password and delete the file. Note in the commit body that the backup is a manual step.

- [ ] **Step 5: Commit**

```bash
git add scripts/sparkle-tools.sh .gitignore Dict-app.xcodeproj/project.pbxproj
git commit -m "chore: Sparkle public key and tool fetcher"
```

---

### Task 10: Release pipeline (B2)

**Files:**
- Create: `Makefile`, `scripts/notarize.sh`, `scripts/publish.sh`, `scripts/appcast.py`, `scripts/version.py`, `fastlane/.env` (gitignored; copy Bench's three ASC lines, pointing `ASC_KEY_PATH` at the same `.p8`), `Dict-app.xcodeproj/xcshareddata/xcschemes/Dict-app.xcscheme` (share the scheme in Xcode or copy it from `xcuserdata`)
- Modify: `RELEASING.md` (rewrite around `make publish`), `appcast.xml` (keep as is; `appcast.py` inserts after `</language>`)

**Interfaces:**
- Produces: `make build`, `make test`, `make notarize`, `make publish NOTES=path.md [VERSION=1.0]`, `make clean`. `Makefile` uses `xcodebuild -project Dict-app.xcodeproj -scheme Dict-app -derivedDataPath build`; `make test` runs `xcodebuild test -destination 'platform=macOS'` skipping `ParakeetEndToEndTests` via `-skip-testing:Dict-appTests/ParakeetEndToEndTests` (it needs the 500 MB model).
- Produces: `scripts/version.py get` → `"<marketing> <build>"` read from `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` in `project.pbxproj`; `scripts/version.py set <marketing> <build>` rewrites every occurrence of both keys in the file.
- Produces: `scripts/notarize.sh` (Bench's, with `TEAM=ZPU7B69KH3`, project `Dict-app.xcodeproj`, scheme `Dict-app`, app name `Dict-app.app`, output zip `build/notarized/Dict-<version>-<build>.zip`, no `xcodegen` step).
- Produces: `scripts/appcast.py` (Bench's, title `Dict <version>`, `minimumSystemVersion` 26.0, `hardwareRequirements` arm64, inserted into this repo's `appcast.xml`).
- Produces: `scripts/publish.sh`, adapted: `RELEASES_REPO=mattbirchler/Dict-app`, no clone of a second repo (the feed is `./appcast.xml`), `FEED_BUILD` read from `./appcast.xml`, `sign_update --account dict`, tag `v<version>-<build>`, release title `Dict <version> (build <build>)` with `--notes-file "$NOTES"`, then `git add appcast.xml && git commit -m "release: <version> build <build>"`, then `git push origin main "$TAG"`. Keeps Bench's guards (release notes required, on `main`, clean tree, in step with origin) and `DRY_RUN=1`.
- Produces: `RELEASING.md` describing: write notes → `make publish NOTES=notes/1.0.md VERSION=1.0` → what the script does → how to recover if a step fails (release created but appcast not pushed: rerun the appcast step by hand; notarization rejected: read `build/notarized/*.log`).

- [ ] **Step 1: Share the scheme and write `Makefile`, `scripts/version.py`, `scripts/notarize.sh`, `scripts/appcast.py`, `scripts/publish.sh`, `fastlane/.env`**

- [ ] **Step 2: Verify `version.py` round-trips**

Run: `python3 scripts/version.py get` → `1.0 1`; `python3 scripts/version.py set 1.0 2 && git diff --stat` → only `project.pbxproj` changed, four `CURRENT_PROJECT_VERSION` lines; then `git checkout Dict-app.xcodeproj/project.pbxproj`.

- [ ] **Step 3: Verify `make build` and `make test`**

Expected: `BUILD SUCCEEDED`, `TEST SUCCEEDED`.

- [ ] **Step 4: Verify `make notarize`**

Expected: last line is a zip path under `build/notarized/`, `spctl --assess` passed inside the script. This is the first real Developer ID + notarization run for this app; if Apple rejects it, the script prints the notarization log.

- [ ] **Step 5: Dry-run publish with throwaway notes**

Write `build/notes-test.md` with two bullets. Run: `DRY_RUN=1 make publish NOTES=build/notes-test.md VERSION=1.0`. Expected: `Dry run done.` and `build/publish/appcast.xml` contains an `<item>` for `1.0` build `2` with an `edSignature`. Then confirm the guards: `touch x && make publish NOTES=build/notes-test.md` (without `DRY_RUN`) must fail with `Commit or stash your changes first.`; `rm x`. `make publish` with no `NOTES` must fail with the release-notes message.

- [ ] **Step 6: Rewrite `RELEASING.md` and commit**

```bash
git add Makefile scripts RELEASING.md Dict-app.xcodeproj/xcshareddata
git commit -m "feat: make publish builds, notarizes, signs, and ships a Sparkle release"
```

---

### Task 11: README, LICENSE, privacy statement (B7)

**Files:**
- Create: `README.md`, `LICENSE` (MIT, `Copyright (c) 2026 Matt Birchler`), `PRIVACY.md`
- Modify: `Dict-app/SettingsView.swift` (About tab's on-device line links nowhere yet; leave it, Task L3 in Phase 4 revisits About)

**Interfaces:**
- `README.md` sections, in order: one-line description (`Dict is a free dictation app for the Mac that runs entirely on your device.`), Requirements (`macOS 26 or later, Apple silicon`), Install (download the latest zip from Releases, unzip, open; Dict offers to move itself to Applications), How to use (hold the hotkey, release to insert; Space for hands-free; Escape to cancel), Engines (Apple, no download; Parakeet, about 500 MB, more accurate), Privacy (two sentences and a link to `PRIVACY.md`), Building (`make build`, `make test`), Releasing (link to `RELEASING.md`), License.
- `PRIVACY.md`: what stays on the Mac (audio, transcripts, history, replacements), the only two network connections (model download from the FluidAudio/Hugging Face host on first use of Parakeet; the Sparkle update check against the GitHub-hosted feed, which sends the app version and macOS version and nothing else), no analytics, no accounts, how to delete everything (quit, delete the app, `~/Library/Application Support/FluidAudio`, and the app's container data).

- [ ] **Step 1: Write the three files.** No em dashes. Check the model download host by reading `AsrModels.downloadAndLoad` in the FluidAudio checkout under DerivedData and name it exactly in `PRIVACY.md`.

- [ ] **Step 2: Commit**

```bash
git add README.md LICENSE PRIVACY.md
git commit -m "docs: README, MIT license, and privacy statement"
```

---

### Task 12: Make the repo public (decision 2)

This is a one-way action and the only task with no code. Ask Matt to confirm in the moment before running it.

- [ ] **Step 1: Confirm with Matt, then run** `gh repo edit mattbirchler/Dict-app --visibility public --accept-visibility-change-consequences`

- [ ] **Step 2: Verify** `gh repo view --json visibility` → `PUBLIC`, and that `https://raw.githubusercontent.com/mattbirchler/Dict-app/main/appcast.xml` loads without auth (`curl -fsI` returns 200).

---

## Self-review notes

- Spec coverage: B1 → Task 9, B2 → Task 10, B3 → Task 8, B4 → Task 4, B5 → Task 2, B6 → Task 6, B7 → Task 11, B8 → Task 3, B9 → Task 1, B10 → Task 5, B11 → Task 7, repo-public decision → Task 12. The Whisper-delete and Apple-first decisions are satisfied by Task 1 (default engine already `.apple` for fresh installs; the auto-upgrade to Parakeet is Phase 2, O3).
- Ordering: Task 1 first because it shrinks everything after it and moves `inputDeviceName` to where Task 7 builds on it. Task 3 (logging) before Task 4 so new HUD code logs through `Log` from the start. Tasks 9 and 10 need Task 2's version values.
- Types: `DictationResult`, `InputDeviceChoice`, `AudioInputDevice`, `HUDScreenPicker.pick`, `ApplicationsMover.shouldOffer`, `PermissionChecker.requiredGranted(for:)` are each defined once and used by name in the tasks that follow.
- Not in scope (Phase 2+): the onboarding rewrite, shortcut recorder, sounds, DMG background, GitHub Actions. Task 10 deliberately ships a zip, matching Bench; L8 swaps in a DMG later without changing the feed.
