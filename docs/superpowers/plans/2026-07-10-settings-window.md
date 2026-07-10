# Settings Window Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the empty `Settings` scene with a real tabbed Settings window (General / History / About) backed by a new `SettingsStore`, adding launch-at-login, a hotkey picker, hold-vs-toggle activation, and history retention controls, per `docs/superpowers/specs/2026-07-10-settings-window-design.md`.

**Architecture:** One `@Observable SettingsStore` owns every persisted preference (UserDefaults writes in `didSet`, plus an `onChange` closure so non-SwiftUI services get values pushed). KeyMonitor's decision logic is extracted into a pure `DictationKeyLogic` struct for testability, then KeyMonitor gains a configurable hotkey and toggle mode. HistoryStore gains a settable limit and `clearAll()`. The SwiftUI `Settings` scene renders three tabs; the popover slims down.

**Tech Stack:** Swift, SwiftUI `Settings` scene, `@Observable`, SwiftData, ServiceManagement (`SMAppService`), Sparkle, Swift Testing (`import Testing`, `@Test`, `#expect`).

## Global Constraints

- Deployment target: macOS 26.4. App is `LSUIElement = YES` (no Dock icon).
- Tests use Swift Testing (`import Testing`), NOT XCTest. Test target: `Dict-appTests`.
- The Xcode project uses file-system-synchronized groups — new `.swift` files under `Dict-app/` or `Dict-appTests/` are picked up automatically; do NOT edit `project.pbxproj`.
- The UserDefaults key `isFormattingEnabled` already exists in the wild and MUST keep that exact name (migration).
- Persistence pattern: property `didSet` writes UserDefaults (same as today's `AppState.isFormattingEnabled`).
- Build command: `xcodebuild build -project Dict-app.xcodeproj -scheme Dict-app -destination 'platform=macOS' -quiet` (if the scheme name differs, check `xcodebuild -list -project Dict-app.xcodeproj` once and use that name everywhere).
- Test command shape: `xcodebuild test -project Dict-app.xcodeproj -scheme Dict-app -destination 'platform=macOS' -only-testing:Dict-appTests/<SuiteName> -quiet`. Never run `EndToEndTranscriptionTests` (slow, downloads a model).
- Commit after every task with the message given in the task.

---

### Task 1: SettingsStore

**Files:**
- Create: `Dict-app/SettingsStore.swift`
- Test: `Dict-appTests/SettingsStoreTests.swift`

**Interfaces:**
- Produces: `SettingsStore` (`@MainActor @Observable`), enums `HotkeyChoice` (`rightCommand|rightControl|rightOption|fn`), `ActivationMode` (`holdToTalk|toggle`), `HistoryLimit` (`off|ten|fifty|twoHundred|unlimited`, with `maxEntries: Int?` and `savesHistory: Bool`), and `SettingsStore.Change` enum + `onChange: ((Change) -> Void)?`. Later tasks depend on these exact names.

- [ ] **Step 1: Write the failing tests**

Create `Dict-appTests/SettingsStoreTests.swift`:

```swift
import Foundation
import Testing
@testable import Dict_app

@MainActor
struct SettingsStoreTests {
    /// Isolated UserDefaults per test so tests can't pollute each other or
    /// the real app preferences.
    private func makeDefaults() -> UserDefaults {
        let name = "SettingsStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func defaultsWhenNothingStored() {
        let store = SettingsStore(defaults: makeDefaults())
        #expect(store.hotkey == .rightCommand)
        #expect(store.activationMode == .holdToTalk)
        #expect(store.isFormattingEnabled == true)
        #expect(store.historyLimit == .fifty)
    }

    @Test func persistsAndReloads() {
        let defaults = makeDefaults()
        let store = SettingsStore(defaults: defaults)
        store.hotkey = .fn
        store.activationMode = .toggle
        store.isFormattingEnabled = false
        store.historyLimit = .unlimited

        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.hotkey == .fn)
        #expect(reloaded.activationMode == .toggle)
        #expect(reloaded.isFormattingEnabled == false)
        #expect(reloaded.historyLimit == .unlimited)
    }

    @Test func migratesExistingFormattingKey() {
        // Users of the current build already have this exact key.
        let defaults = makeDefaults()
        defaults.set(false, forKey: "isFormattingEnabled")
        let store = SettingsStore(defaults: defaults)
        #expect(store.isFormattingEnabled == false)
    }

    @Test func ignoresCorruptStoredValues() {
        let defaults = makeDefaults()
        defaults.set("not-a-real-hotkey", forKey: "hotkey")
        defaults.set("nope", forKey: "historyLimit")
        let store = SettingsStore(defaults: defaults)
        #expect(store.hotkey == .rightCommand)
        #expect(store.historyLimit == .fifty)
    }

    @Test func firesOnChangeForEachProperty() {
        let store = SettingsStore(defaults: makeDefaults())
        var changes: [SettingsStore.Change] = []
        store.onChange = { changes.append($0) }
        store.hotkey = .rightOption
        store.activationMode = .toggle
        store.isFormattingEnabled = false
        store.historyLimit = .ten
        #expect(changes == [.hotkey, .activationMode, .formatting, .historyLimit])
    }

    @Test func historyLimitMapping() {
        #expect(HistoryLimit.off.maxEntries == 0)
        #expect(HistoryLimit.ten.maxEntries == 10)
        #expect(HistoryLimit.fifty.maxEntries == 50)
        #expect(HistoryLimit.twoHundred.maxEntries == 200)
        #expect(HistoryLimit.unlimited.maxEntries == nil)
        #expect(!HistoryLimit.off.savesHistory)
        #expect(HistoryLimit.ten.savesHistory)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Dict-app.xcodeproj -scheme Dict-app -destination 'platform=macOS' -only-testing:Dict-appTests/SettingsStoreTests -quiet`
Expected: BUILD FAILS — `cannot find 'SettingsStore' in scope`.

- [ ] **Step 3: Implement SettingsStore**

Create `Dict-app/SettingsStore.swift`:

```swift
import Foundation

enum HotkeyChoice: String, CaseIterable {
    case rightCommand, rightControl, rightOption, fn

    var displayName: String {
        switch self {
        case .rightCommand: "Right Command (⌘)"
        case .rightControl: "Right Control (⌃)"
        case .rightOption: "Right Option (⌥)"
        case .fn: "Fn / Globe (🌐)"
        }
    }
}

enum ActivationMode: String, CaseIterable {
    case holdToTalk, toggle

    var displayName: String {
        switch self {
        case .holdToTalk: "Press and hold"
        case .toggle: "Press to start and stop"
        }
    }
}

enum HistoryLimit: String, CaseIterable {
    case off, ten, fifty, twoHundred, unlimited

    /// Maximum stored entries; nil means unlimited.
    var maxEntries: Int? {
        switch self {
        case .off: 0
        case .ten: 10
        case .fifty: 50
        case .twoHundred: 200
        case .unlimited: nil
        }
    }

    var savesHistory: Bool { self != .off }

    var displayName: String {
        switch self {
        case .off: "Off"
        case .ten: "Last 10"
        case .fifty: "Last 50"
        case .twoHundred: "Last 200"
        case .unlimited: "Unlimited"
        }
    }
}

/// Owns every persisted preference. Each property writes UserDefaults on set
/// and fires `onChange` so non-SwiftUI services (KeyMonitor, HistoryStore,
/// PipelineCoordinator) can be reconfigured; SwiftUI observes directly.
@MainActor
@Observable
final class SettingsStore {
    enum Change { case hotkey, activationMode, formatting, historyLimit }

    @ObservationIgnored var onChange: ((Change) -> Void)?
    @ObservationIgnored private let defaults: UserDefaults

    private enum Keys {
        static let hotkey = "hotkey"
        static let activationMode = "activationMode"
        // Pre-existing key from earlier builds — do not rename.
        static let isFormattingEnabled = "isFormattingEnabled"
        static let historyLimit = "historyLimit"
    }

    var hotkey: HotkeyChoice {
        didSet {
            defaults.set(hotkey.rawValue, forKey: Keys.hotkey)
            onChange?(.hotkey)
        }
    }

    var activationMode: ActivationMode {
        didSet {
            defaults.set(activationMode.rawValue, forKey: Keys.activationMode)
            onChange?(.activationMode)
        }
    }

    var isFormattingEnabled: Bool {
        didSet {
            defaults.set(isFormattingEnabled, forKey: Keys.isFormattingEnabled)
            onChange?(.formatting)
        }
    }

    var historyLimit: HistoryLimit {
        didSet {
            defaults.set(historyLimit.rawValue, forKey: Keys.historyLimit)
            onChange?(.historyLimit)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hotkey = defaults.string(forKey: Keys.hotkey)
            .flatMap(HotkeyChoice.init(rawValue:)) ?? .rightCommand
        self.activationMode = defaults.string(forKey: Keys.activationMode)
            .flatMap(ActivationMode.init(rawValue:)) ?? .holdToTalk
        self.isFormattingEnabled = defaults.object(forKey: Keys.isFormattingEnabled) as? Bool ?? true
        self.historyLimit = defaults.string(forKey: Keys.historyLimit)
            .flatMap(HistoryLimit.init(rawValue:)) ?? .fifty
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project Dict-app.xcodeproj -scheme Dict-app -destination 'platform=macOS' -only-testing:Dict-appTests/SettingsStoreTests -quiet`
Expected: all 6 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Dict-app/SettingsStore.swift Dict-appTests/SettingsStoreTests.swift
git commit -m "feat: add SettingsStore with persisted hotkey, mode, formatting, and history preferences"
```

---

### Task 2: DictationKeyLogic (pure hotkey state machine)

**Files:**
- Create: `Dict-app/DictationKeyLogic.swift`
- Test: `Dict-appTests/DictationKeyLogicTests.swift`

**Interfaces:**
- Consumes: `ActivationMode` from Task 1.
- Produces: `struct DictationKeyLogic` with `var mode: ActivationMode`, `private(set) var isKeyHeld/isRecording/handsFreeMode`, `mutating func hotkeyDown(now:) -> Action?`, `mutating func hotkeyUp(now:) -> Action?`, `mutating func spaceDown() -> Action?`, `var shouldSwallowSpace: Bool`, `mutating func reset() -> Action?`, `enum Action { case start, stop, cancel, enterHandsFree }`, `static let holdThreshold: Duration`. Task 3 wires this into KeyMonitor.

- [ ] **Step 1: Write the failing tests**

Create `Dict-appTests/DictationKeyLogicTests.swift`:

```swift
import Foundation
import Testing
@testable import Dict_app

struct DictationKeyLogicTests {
    private let t0 = ContinuousClock().now

    // MARK: Hold-to-talk (today's behavior)

    @Test func holdPressStartsRecording() {
        var logic = DictationKeyLogic(mode: .holdToTalk)
        #expect(logic.hotkeyDown(now: t0) == .start)
        #expect(logic.isRecording)
    }

    @Test func holdReleaseAfterThresholdStops() {
        var logic = DictationKeyLogic(mode: .holdToTalk)
        _ = logic.hotkeyDown(now: t0)
        #expect(logic.hotkeyUp(now: t0 + .milliseconds(200)) == .stop)
        #expect(!logic.isRecording)
    }

    @Test func holdShortTapCancels() {
        var logic = DictationKeyLogic(mode: .holdToTalk)
        _ = logic.hotkeyDown(now: t0)
        #expect(logic.hotkeyUp(now: t0 + .milliseconds(50)) == .cancel)
        #expect(!logic.isRecording)
    }

    @Test func duplicateDownEventsAreIgnoredWhileHeld() {
        var logic = DictationKeyLogic(mode: .holdToTalk)
        _ = logic.hotkeyDown(now: t0)
        #expect(logic.hotkeyDown(now: t0 + .milliseconds(10)) == nil)
    }

    // MARK: Hands-free (Space while holding)

    @Test func spaceWhileHoldingEntersHandsFree() {
        var logic = DictationKeyLogic(mode: .holdToTalk)
        _ = logic.hotkeyDown(now: t0)
        #expect(logic.shouldSwallowSpace)
        #expect(logic.spaceDown() == .enterHandsFree)
        #expect(logic.handsFreeMode)
        #expect(!logic.shouldSwallowSpace)
    }

    @Test func handsFreeSurvivesKeyRelease() {
        var logic = DictationKeyLogic(mode: .holdToTalk)
        _ = logic.hotkeyDown(now: t0)
        _ = logic.spaceDown()
        #expect(logic.hotkeyUp(now: t0 + .milliseconds(500)) == nil)
        #expect(logic.isRecording)
    }

    @Test func hotkeyPressStopsHandsFree() {
        var logic = DictationKeyLogic(mode: .holdToTalk)
        _ = logic.hotkeyDown(now: t0)
        _ = logic.spaceDown()
        _ = logic.hotkeyUp(now: t0 + .milliseconds(500))
        #expect(logic.hotkeyDown(now: t0 + .seconds(2)) == .stop)
        #expect(!logic.isRecording)
        #expect(!logic.handsFreeMode)
    }

    @Test func spaceWhenNotRecordingDoesNothing() {
        var logic = DictationKeyLogic(mode: .holdToTalk)
        #expect(logic.spaceDown() == nil)
        #expect(!logic.shouldSwallowSpace)
    }

    // MARK: Toggle mode

    @Test func togglePressStartsThenStops() {
        var logic = DictationKeyLogic(mode: .toggle)
        #expect(logic.hotkeyDown(now: t0) == .start)
        #expect(logic.hotkeyUp(now: t0 + .milliseconds(80)) == nil)
        #expect(logic.isRecording)
        #expect(logic.hotkeyDown(now: t0 + .seconds(3)) == .stop)
        #expect(!logic.isRecording)
    }

    @Test func toggleIgnoresSpaceEntirely() {
        var logic = DictationKeyLogic(mode: .toggle)
        _ = logic.hotkeyDown(now: t0)
        _ = logic.hotkeyUp(now: t0 + .milliseconds(80))
        #expect(logic.spaceDown() == nil)
        #expect(!logic.shouldSwallowSpace)
    }

    // MARK: Reset (hotkey/mode changed or monitor uninstalled)

    @Test func resetWhileRecordingRequestsStop() {
        var logic = DictationKeyLogic(mode: .toggle)
        _ = logic.hotkeyDown(now: t0)
        #expect(logic.reset() == .stop)
        #expect(!logic.isRecording)
        #expect(!logic.handsFreeMode)
    }

    @Test func resetWhileIdleDoesNothing() {
        var logic = DictationKeyLogic(mode: .holdToTalk)
        #expect(logic.reset() == nil)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Dict-app.xcodeproj -scheme Dict-app -destination 'platform=macOS' -only-testing:Dict-appTests/DictationKeyLogicTests -quiet`
Expected: BUILD FAILS — `cannot find 'DictationKeyLogic' in scope`.

- [ ] **Step 3: Implement DictationKeyLogic**

Create `Dict-app/DictationKeyLogic.swift`:

```swift
import Foundation

/// Pure decision logic for the dictation hotkey — extracted from KeyMonitor
/// so mode and state transitions can be unit tested without CGEvents.
struct DictationKeyLogic {
    enum Action: Equatable { case start, stop, cancel, enterHandsFree }

    /// Recording starts immediately on key-down so no speech is lost;
    /// hold-mode releases shorter than this count as accidental taps.
    static let holdThreshold: Duration = .milliseconds(150)

    var mode: ActivationMode
    private(set) var isKeyHeld = false
    private(set) var isRecording = false
    private(set) var handsFreeMode = false
    private var keyDownTime: ContinuousClock.Instant?

    init(mode: ActivationMode = .holdToTalk) {
        self.mode = mode
    }

    mutating func hotkeyDown(now: ContinuousClock.Instant = ContinuousClock().now) -> Action? {
        guard !isKeyHeld else { return nil }
        isKeyHeld = true

        switch mode {
        case .holdToTalk:
            if handsFreeMode {
                handsFreeMode = false
                isRecording = false
                return .stop
            }
            isRecording = true
            keyDownTime = now
            return .start
        case .toggle:
            if isRecording {
                isRecording = false
                return .stop
            }
            isRecording = true
            return .start
        }
    }

    mutating func hotkeyUp(now: ContinuousClock.Instant = ContinuousClock().now) -> Action? {
        isKeyHeld = false
        guard mode == .holdToTalk, !handsFreeMode, isRecording else { return nil }

        isRecording = false
        let heldLongEnough = keyDownTime.map { now - $0 >= Self.holdThreshold } ?? true
        keyDownTime = nil
        return heldLongEnough ? .stop : .cancel
    }

    mutating func spaceDown() -> Action? {
        guard mode == .holdToTalk, isRecording, isKeyHeld, !handsFreeMode else { return nil }
        handsFreeMode = true
        return .enterHandsFree
    }

    /// Whether a Space key-down should be swallowed instead of passed to the
    /// frontmost app (it's about to switch us into hands-free mode).
    var shouldSwallowSpace: Bool {
        mode == .holdToTalk && isRecording && !handsFreeMode
    }

    /// Called when the hotkey or mode changes, or monitoring stops. Returns
    /// .stop if a recording was in flight so the owner can finish it cleanly.
    mutating func reset() -> Action? {
        let wasRecording = isRecording
        isKeyHeld = false
        isRecording = false
        handsFreeMode = false
        keyDownTime = nil
        return wasRecording ? .stop : nil
    }
}
```

Note: `hotkeyPressStopsHandsFree` requires the hands-free stop branch to run even though `isKeyHeld` was just set — the `guard !isKeyHeld` sits before the switch, and `hotkeyUp` in hands-free mode already cleared `isKeyHeld`, so the flow works: down(start) → space(hands-free) → up(nil, clears held) → down(stop).

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project Dict-app.xcodeproj -scheme Dict-app -destination 'platform=macOS' -only-testing:Dict-appTests/DictationKeyLogicTests -quiet`
Expected: all 12 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Dict-app/DictationKeyLogic.swift Dict-appTests/DictationKeyLogicTests.swift
git commit -m "feat: extract testable DictationKeyLogic with hold and toggle activation modes"
```

---

### Task 3: KeyMonitor — configurable hotkey + modes

**Files:**
- Modify: `Dict-app/KeyMonitor.swift` (full rewrite of internals; callbacks keep their names)

**Interfaces:**
- Consumes: `DictationKeyLogic`, `HotkeyChoice`, `ActivationMode`.
- Produces: `KeyMonitor.hotkey: HotkeyChoice` and `KeyMonitor.activationMode: ActivationMode` (both safe to set at runtime; if set mid-recording they fire `onRecordingStop` first). Existing callback properties keep working: `onRecordingStart`, `onRecordingStop`, `onRecordingCancel`, `onHandsFreeChanged`, `install()`, `uninstall()`.

- [ ] **Step 1: Rewrite KeyMonitor around DictationKeyLogic**

Replace the contents of `Dict-app/KeyMonitor.swift` with:

```swift
import CoreGraphics
import Foundation

extension HotkeyChoice {
    var keycode: Int64 {
        switch self {
        case .rightCommand: 54
        case .rightControl: 62
        case .rightOption: 61
        case .fn: 63
        }
    }

    var flagMask: CGEventFlags {
        switch self {
        case .rightCommand: .maskCommand
        case .rightControl: .maskControl
        case .rightOption: .maskAlternate
        case .fn: .maskSecondaryFn
        }
    }
}

final class KeyMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// All state transitions live in the pure logic struct. The event tap
    /// callback runs on the main run loop (see install()), so access is
    /// single-threaded even though this class isn't actor-isolated.
    private var logic = DictationKeyLogic()

    var hotkey: HotkeyChoice = .rightCommand {
        didSet { resetLogic() }
    }

    var activationMode: ActivationMode {
        get { logic.mode }
        set {
            resetLogic()
            logic.mode = newValue
        }
    }

    var onRecordingStart: (() -> Void)?
    var onRecordingStop: (() -> Void)?
    /// Fired instead of onRecordingStop when the key is released before
    /// holdThreshold — the recording should be discarded, not transcribed.
    var onRecordingCancel: (() -> Void)?
    var onHandsFreeChanged: ((Bool) -> Void)?

    private static let spaceKeycode: Int64 = 49

    func install() -> Bool {
        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: KeyMonitor.eventCallback,
            userInfo: refcon
        ) else {
            return false
        }

        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func uninstall() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        eventTap = nil
        runLoopSource = nil
        _ = logic.reset()
    }

    nonisolated private static let eventCallback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let monitor = Unmanaged<KeyMonitor>.fromOpaque(refcon).takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = monitor.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let keycode = event.getIntegerValueField(.keyboardEventKeycode)

        // Spacebar while holding the hotkey: switch to hands-free mode.
        if type == .keyDown && keycode == spaceKeycode {
            let swallow = monitor.logic.shouldSwallowSpace && !monitor.logic.handsFreeMode
            monitor.perform(monitor.logic.spaceDown())
            return swallow ? nil : Unmanaged.passUnretained(event)
        }

        guard keycode == monitor.hotkey.keycode else {
            return Unmanaged.passUnretained(event)
        }

        let isDown = event.flags.contains(monitor.hotkey.flagMask)
        if isDown && !monitor.logic.isKeyHeld {
            monitor.perform(monitor.logic.hotkeyDown())
        } else if !isDown && monitor.logic.isKeyHeld {
            monitor.perform(monitor.logic.hotkeyUp())
        }

        return Unmanaged.passUnretained(event)
    }

    private func perform(_ action: DictationKeyLogic.Action?) {
        guard let action else { return }
        Task { @MainActor in
            switch action {
            case .start: self.onRecordingStart?()
            case .stop: self.onRecordingStop?()
            case .cancel: self.onRecordingCancel?()
            case .enterHandsFree: self.onHandsFreeChanged?(true)
            }
        }
    }

    /// Hotkey or mode changed. If a recording is in flight, finish it
    /// cleanly (transcribe what was said) before adopting the new config.
    private func resetLogic() {
        perform(logic.reset())
    }
}
```

Behavior notes (must hold after the rewrite):
- The swallow decision is made *before* `spaceDown()` mutates state, so the Space press that activates hands-free is still swallowed (same as today).
- The old dual right-⌘/right-⌃ trigger is intentionally replaced by the single configured hotkey (spec: single-choice picker, default Right ⌘).

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild build -project Dict-app.xcodeproj -scheme Dict-app -destination 'platform=macOS' -quiet`
Expected: build succeeds (AppDelegate still compiles unchanged — `hotkey`/`activationMode` have defaults matching old behavior minus the right-⌃ alias).

- [ ] **Step 3: Run the logic tests again (regression)**

Run: `xcodebuild test -project Dict-app.xcodeproj -scheme Dict-app -destination 'platform=macOS' -only-testing:Dict-appTests/DictationKeyLogicTests -quiet`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add Dict-app/KeyMonitor.swift
git commit -m "feat: KeyMonitor uses configurable hotkey and activation mode via DictationKeyLogic"
```

---

### Task 4: HistoryStore — retention limit + clearAll

**Files:**
- Modify: `Dict-app/HistoryStore.swift`
- Test: `Dict-appTests/HistoryStoreTests.swift`

**Interfaces:**
- Consumes: `HistoryLimit` from Task 1.
- Produces: `HistoryStore` becomes `@MainActor`; gains `init(inMemory: Bool = false)`, `var limit: HistoryLimit` (default `.fifty`; lowering it prunes immediately), `func save(cleanedText:)` no-ops when `limit == .off`, `func clearAll()`. `save(cleanedText:)` also gains an internal-use `timestamp: Date = Date()` parameter for tests.

- [ ] **Step 1: Write the failing tests**

Create `Dict-appTests/HistoryStoreTests.swift`:

```swift
import Foundation
import Testing
@testable import Dict_app

@MainActor
struct HistoryStoreTests {
    private func makeStore() -> HistoryStore {
        HistoryStore(inMemory: true)
    }

    /// Distinct, ordered timestamps so sort order is deterministic.
    private func fill(_ store: HistoryStore, count: Int) {
        let base = Date(timeIntervalSince1970: 1_000_000)
        for i in 0..<count {
            store.save(cleanedText: "entry \(i)", timestamp: base.addingTimeInterval(Double(i)))
        }
    }

    @Test func savesAndPrunesToLimit() {
        let store = makeStore()
        store.limit = .ten
        fill(store, count: 12)
        #expect(store.recentEntries.count == 10)
        #expect(store.recentEntries.first?.cleanedText == "entry 11")
        #expect(store.recentEntries.last?.cleanedText == "entry 2")
    }

    @Test func offMeansNothingIsSaved() {
        let store = makeStore()
        store.limit = .off
        fill(store, count: 3)
        #expect(store.recentEntries.isEmpty)
    }

    @Test func offKeepsExistingEntries() {
        let store = makeStore()
        fill(store, count: 5)
        store.limit = .off
        #expect(store.recentEntries.count == 5)
    }

    @Test func loweringLimitPrunesImmediately() {
        let store = makeStore()
        fill(store, count: 30)
        #expect(store.recentEntries.count == 30)
        store.limit = .ten
        #expect(store.recentEntries.count == 10)
        #expect(store.recentEntries.first?.cleanedText == "entry 29")
    }

    @Test func unlimitedNeverPrunes() {
        let store = makeStore()
        store.limit = .unlimited
        fill(store, count: 60)
        #expect(store.recentEntries.count == 60)
    }

    @Test func clearAllDeletesEverything() {
        let store = makeStore()
        fill(store, count: 8)
        store.clearAll()
        #expect(store.recentEntries.isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Dict-app.xcodeproj -scheme Dict-app -destination 'platform=macOS' -only-testing:Dict-appTests/HistoryStoreTests -quiet`
Expected: BUILD FAILS — no `init(inMemory:)`, no `limit`, no `timestamp:` parameter.

- [ ] **Step 3: Implement the HistoryStore changes**

Replace the contents of `Dict-app/HistoryStore.swift` with:

```swift
import Foundation
import SwiftData

@MainActor
@Observable
final class HistoryStore {
    private let container: ModelContainer

    /// Retention policy, pushed in from SettingsStore. Lowering the limit
    /// prunes immediately; .off stops saving but keeps existing entries.
    var limit: HistoryLimit = .fifty {
        didSet {
            guard limit != oldValue else { return }
            pruneOldEntries(context: container.mainContext)
            try? container.mainContext.save()
            fetchEntries()
        }
    }

    var recentEntries: [TranscriptionEntry] = []

    init(inMemory: Bool = false) {
        let schema = Schema([TranscriptionEntry.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            self.container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        fetchEntries()
    }

    func save(cleanedText: String, timestamp: Date = Date()) {
        guard limit.savesHistory else { return }
        let context = container.mainContext
        let entry = TranscriptionEntry(cleanedText: cleanedText, timestamp: timestamp)
        context.insert(entry)
        pruneOldEntries(context: context)
        try? context.save()
        fetchEntries()
    }

    func clearAll() {
        let context = container.mainContext
        try? context.delete(model: TranscriptionEntry.self)
        try? context.save()
        fetchEntries()
    }

    func fetchEntries() {
        let context = container.mainContext
        let descriptor = FetchDescriptor<TranscriptionEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        recentEntries = (try? context.fetch(descriptor)) ?? []
    }

    private func pruneOldEntries(context: ModelContext) {
        guard let maxEntries = limit.maxEntries, maxEntries > 0 else { return }
        let descriptor = FetchDescriptor<TranscriptionEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        guard let all = try? context.fetch(descriptor), all.count > maxEntries else { return }
        for entry in all.dropFirst(maxEntries) {
            context.delete(entry)
        }
    }
}
```

Note: `pruneOldEntries` guards `maxEntries > 0` so `.off` (maxEntries 0) never mass-deletes — `.off` only blocks new saves, per spec.

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project Dict-app.xcodeproj -scheme Dict-app -destination 'platform=macOS' -only-testing:Dict-appTests/HistoryStoreTests -quiet`
Expected: all 6 tests PASS.

- [ ] **Step 5: Build the app target (PipelineCoordinator calls `save(cleanedText:)` — still compiles because `timestamp` has a default)**

Run: `xcodebuild build -project Dict-app.xcodeproj -scheme Dict-app -destination 'platform=macOS' -quiet`
Expected: build succeeds.

- [ ] **Step 6: Commit**

```bash
git add Dict-app/HistoryStore.swift Dict-appTests/HistoryStoreTests.swift
git commit -m "feat: HistoryStore retention limit, off mode, and clearAll"
```

---

### Task 5: Wire SettingsStore into AppState and AppDelegate

**Files:**
- Modify: `Dict-app/AppState.swift`
- Modify: `Dict-app/Dict_appApp.swift` (AppDelegate wiring only)

**Interfaces:**
- Consumes: `SettingsStore`, `KeyMonitor.hotkey/activationMode`, `HistoryStore.limit`.
- Produces: `AppState.settings: SettingsStore`; `AppState.isFormattingEnabled` becomes a computed passthrough (kept so the popover compiles until Task 8); `AppState.onHotkeySettingsChanged: (() -> Void)?` fired for `.hotkey`/`.activationMode` changes.

- [ ] **Step 1: Rework AppState around SettingsStore**

In `Dict-app/AppState.swift`, replace the stored `isFormattingEnabled` property and `init` with:

```swift
@MainActor
@Observable
final class AppState {
    let settings: SettingsStore
    let permissionChecker = PermissionChecker()
    let pipeline = PipelineCoordinator()

    var isEnabled = true {
        didSet { onEnabledChanged?(isEnabled) }
    }
    /// Passthrough for the popover toggle; the stored value lives in
    /// SettingsStore now (same UserDefaults key as before).
    var isFormattingEnabled: Bool {
        get { settings.isFormattingEnabled }
        set { settings.isFormattingEnabled = newValue }
    }
    var onEnabledChanged: ((Bool) -> Void)?
    var onProcessingComplete: (() -> Void)?
    /// Fired when the hotkey or activation mode setting changes so the
    /// AppDelegate can reconfigure the KeyMonitor.
    var onHotkeySettingsChanged: (() -> Void)?
    var isRecording = false
    var isProcessing = false
    var isLoadingWhisper = false
    var whisperDownloadProgress: Double = 0
    var lastError: String?
    var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") }
        set { UserDefaults.standard.set(newValue, forKey: "hasCompletedOnboarding") }
    }

    init(settings: SettingsStore = SettingsStore()) {
        self.settings = settings
        pipeline.isFormattingEnabled = settings.isFormattingEnabled
        pipeline.historyStore.limit = settings.historyLimit
        settings.onChange = { [weak self] change in
            guard let self else { return }
            switch change {
            case .formatting:
                self.pipeline.isFormattingEnabled = self.settings.isFormattingEnabled
            case .historyLimit:
                self.pipeline.historyStore.limit = self.settings.historyLimit
            case .hotkey, .activationMode:
                self.onHotkeySettingsChanged?()
            }
        }
    }
    // ... preloadWhisperModel / startRecording / cancelRecording /
    // stopRecording stay exactly as they are today ...
}
```

- [ ] **Step 2: Wire KeyMonitor configuration in AppDelegate**

In `Dict-app/Dict_appApp.swift`, inside `applicationDidFinishLaunching`, immediately before the `if appState.permissionChecker.accessibilityGranted && appState.isEnabled` block, add:

```swift
keyMonitor.hotkey = appState.settings.hotkey
keyMonitor.activationMode = appState.settings.activationMode
appState.onHotkeySettingsChanged = { [weak self] in
    guard let self else { return }
    self.keyMonitor.hotkey = self.appState.settings.hotkey
    self.keyMonitor.activationMode = self.appState.settings.activationMode
}
```

(Setting `hotkey`/`activationMode` mid-recording fires `onRecordingStop` from `resetLogic()`, which routes through the existing stop flow — HUD shows Processing, transcript is inserted.)

- [ ] **Step 3: Build and run store tests**

Run: `xcodebuild build -project Dict-app.xcodeproj -scheme Dict-app -destination 'platform=macOS' -quiet`
Expected: build succeeds (popover still binds `$appState.isFormattingEnabled` — now hits the passthrough).

Run: `xcodebuild test -project Dict-app.xcodeproj -scheme Dict-app -destination 'platform=macOS' -only-testing:Dict-appTests/SettingsStoreTests -only-testing:Dict-appTests/HistoryStoreTests -quiet`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add Dict-app/AppState.swift Dict-app/Dict_appApp.swift
git commit -m "feat: wire SettingsStore through AppState into pipeline, history, and key monitor"
```

---

### Task 6: Settings window — scene, General tab, launch at login

**Files:**
- Create: `Dict-app/LoginItemManager.swift`
- Create: `Dict-app/SettingsView.swift` (tab container + General tab; History/About tabs arrive in Task 7 as placeholders here)
- Modify: `Dict-app/Dict_appApp.swift` (Settings scene)

**Interfaces:**
- Consumes: `SettingsStore`, `AppState.settings`, `UpdaterViewModel` (defined in `MenuBarPopover.swift`), `SPUUpdater`.
- Produces: `SettingsView(appState:updater:)`, `GeneralSettingsTab(settings:)`, `LoginItemManager` (`@MainActor @Observable`, `var isEnabled: Bool` with register/unregister side effects, `private(set) var requiresApproval: Bool`, `private(set) var lastError: String?`, `func refresh()`).

- [ ] **Step 1: Implement LoginItemManager**

Create `Dict-app/LoginItemManager.swift`:

```swift
import Foundation
import ServiceManagement

/// Bridges SMAppService.mainApp into an observable toggle. The service is
/// the source of truth — nothing is stored in UserDefaults.
@MainActor
@Observable
final class LoginItemManager {
    var isEnabled: Bool {
        didSet {
            guard !isRefreshing, oldValue != isEnabled else { return }
            apply(isEnabled)
        }
    }
    private(set) var requiresApproval: Bool
    private(set) var lastError: String?
    @ObservationIgnored private var isRefreshing = false

    init() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        requiresApproval = status == .requiresApproval
    }

    func refresh() {
        isRefreshing = true
        defer { isRefreshing = false }
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        requiresApproval = status == .requiresApproval
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func apply(_ enabled: Bool) {
        lastError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            lastError = "Couldn't update login item: \(error.localizedDescription)"
        }
        refresh()
    }
}
```

- [ ] **Step 2: Implement SettingsView with the General tab**

Create `Dict-app/SettingsView.swift`:

```swift
import SwiftUI
import Sparkle

struct SettingsView: View {
    @Bindable var appState: AppState
    let updater: SPUUpdater

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsTab(settings: appState.settings)
            }
            Tab("History", systemImage: "clock.arrow.circlepath") {
                Text("History settings coming in Task 7")
            }
            Tab("About", systemImage: "info.circle") {
                Text("About coming in Task 7")
            }
        }
        .frame(width: 480)
    }
}

struct GeneralSettingsTab: View {
    @Bindable var settings: SettingsStore
    @State private var loginItem = LoginItemManager()

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $loginItem.isEnabled)
                if loginItem.requiresApproval {
                    HStack {
                        Text("Waiting for approval in System Settings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Open Login Items…") {
                            loginItem.openLoginItemsSettings()
                        }
                        .controlSize(.small)
                    }
                }
                if let error = loginItem.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Picker("Dictation hotkey", selection: $settings.hotkey) {
                    ForEach(HotkeyChoice.allCases, id: \.self) { choice in
                        Text(choice.displayName).tag(choice)
                    }
                }
                if settings.hotkey == .fn {
                    Text("If pressing 🌐 opens the emoji picker, set “Press 🌐 key to” to “Do Nothing” in System Settings > Keyboard.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Picker("Activation", selection: $settings.activationMode) {
                    ForEach(ActivationMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                Text(activationCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Format transcripts", isOn: $settings.isFormattingEnabled)
                Text("Add punctuation and capitalization with the on-device Apple Intelligence model. Turn off to insert the raw transcript as spoken.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { loginItem.refresh() }
    }

    private var activationCaption: String {
        switch settings.activationMode {
        case .holdToTalk:
            "Hold the hotkey and speak; release to insert. Tap Space while holding to go hands-free, then press the hotkey to finish."
        case .toggle:
            "Press the hotkey to start recording; press it again to stop and insert."
        }
    }
}
```

- [ ] **Step 3: Hook up the Settings scene**

In `Dict-app/Dict_appApp.swift`, replace the scene body:

```swift
var body: some Scene {
    Settings {
        SettingsView(
            appState: appDelegate.appState,
            updater: appDelegate.updaterController.updater
        )
    }
}
```

- [ ] **Step 4: Build**

Run: `xcodebuild build -project Dict-app.xcodeproj -scheme Dict-app -destination 'platform=macOS' -quiet`
Expected: build succeeds.

- [ ] **Step 5: Commit**

```bash
git add Dict-app/LoginItemManager.swift Dict-app/SettingsView.swift Dict-app/Dict_appApp.swift
git commit -m "feat: Settings window with General tab — launch at login, hotkey, activation mode, formatting"
```

---

### Task 7: History and About tabs

**Files:**
- Modify: `Dict-app/SettingsView.swift` (replace the two placeholder tabs)

**Interfaces:**
- Consumes: `SettingsStore.historyLimit`, `HistoryStore.clearAll()`, `UpdaterViewModel` (from `MenuBarPopover.swift`), `SPUUpdater`.
- Produces: `HistorySettingsTab(settings:historyStore:)`, `AboutSettingsTab(updater:)`.

- [ ] **Step 1: Replace the placeholders in SettingsView.swift**

In `SettingsView.body`, replace the two placeholder tabs:

```swift
Tab("History", systemImage: "clock.arrow.circlepath") {
    HistorySettingsTab(
        settings: appState.settings,
        historyStore: appState.pipeline.historyStore
    )
}
Tab("About", systemImage: "info.circle") {
    AboutSettingsTab(updater: updater)
}
```

Append to the same file:

```swift
struct HistorySettingsTab: View {
    @Bindable var settings: SettingsStore
    let historyStore: HistoryStore
    @State private var confirmingClear = false

    var body: some View {
        Form {
            Section {
                Picker("Keep history", selection: $settings.historyLimit) {
                    ForEach(HistoryLimit.allCases, id: \.self) { limit in
                        Text(limit.displayName).tag(limit)
                    }
                }
                Text("Transcriptions are stored only on this Mac. “Off” stops saving new transcriptions; items already saved stay until you clear them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Clear History…", role: .destructive) {
                    confirmingClear = true
                }
                .confirmationDialog(
                    "Delete all saved transcriptions?",
                    isPresented: $confirmingClear
                ) {
                    Button("Clear History", role: .destructive) {
                        historyStore.clearAll()
                    }
                } message: {
                    Text("This removes every saved transcription from this Mac. It can't be undone.")
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct AboutSettingsTab: View {
    @StateObject private var updaterViewModel: UpdaterViewModel

    init(updater: SPUUpdater) {
        self._updaterViewModel = StateObject(wrappedValue: UpdaterViewModel(updater: updater))
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(version) (\(build))"
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            Text("Dict")
                .font(.title2.bold())
            Text(versionString)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("100% on-device: transcription, formatting, and history never leave this Mac.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Button("Check for Updates…") {
                updaterViewModel.checkForUpdates()
            }
            .disabled(!updaterViewModel.canCheckForUpdates)

            Text("Built with WhisperKit and Sparkle.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild build -project Dict-app.xcodeproj -scheme Dict-app -destination 'platform=macOS' -quiet`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Dict-app/SettingsView.swift
git commit -m "feat: History and About settings tabs"
```

---

### Task 8: Popover cleanup + Settings… button

**Files:**
- Modify: `Dict-app/MenuBarPopover.swift`
- Modify: `Dict-app/MenuBarManager.swift`
- Modify: `Dict-app/Dict_appApp.swift` (setup call)
- Modify: `Dict-app/AppState.swift` (remove the `isFormattingEnabled` passthrough)

**Interfaces:**
- Consumes: `openSettings` environment action.
- Produces: `MenuBarPopover(appState:onShowOnboarding:onOpenedSettings:)` (no more `updater` param); `MenuBarManager.setup(appState:onShowOnboarding:)` (drops `updater`).

- [ ] **Step 1: Slim down MenuBarPopover**

In `Dict-app/MenuBarPopover.swift`:

1. Delete the `UpdaterViewModel` usage from the popover but MOVE the `UpdaterViewModel` class definition into `Dict-app/SettingsView.swift` (it's now only used by AboutSettingsTab). Remove `import Sparkle` and `import Combine` from `MenuBarPopover.swift`; add `import Combine` to `SettingsView.swift`.
2. Replace the struct with:

```swift
struct MenuBarPopover: View {
    @Bindable var appState: AppState
    var onShowOnboarding: () -> Void
    /// Called after the Settings window is opened so the owner can close
    /// the popover.
    var onOpenedSettings: () -> Void
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Quick mute
            Toggle("Dictation Enabled", isOn: $appState.isEnabled)
                .toggleStyle(.switch)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider()

            // ... permission warning, model download, processing, error, and
            // history sections stay EXACTLY as they are today ...

            Divider()

            Button("Settings…") {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
                onOpenedSettings()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .buttonStyle(.plain)

            Divider()

            Button("Quit Dict") {
                NSApp.terminate(nil)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .buttonStyle(.plain)
        }
        .frame(width: 320)
    }
}
```

(The "Format Transcripts" toggle and "Check for Updates…" button are gone; `HistoryEntryRow` stays unchanged.)

If `openSettings()` does not open the window when invoked from the NSPopover-hosted view (known LSUIElement quirk — verify manually in Task 9), replace the `openSettings()` call with:

```swift
NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
```

- [ ] **Step 2: Update MenuBarManager**

In `Dict-app/MenuBarManager.swift`, change `setup` to drop the updater and close the popover after Settings opens:

```swift
func setup(appState: AppState, onShowOnboarding: @escaping () -> Void) {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    if let button = statusItem.button {
        button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Dict")
        button.action = #selector(togglePopover)
        button.target = self
    }

    let popover = NSPopover()
    popover.contentSize = NSSize(width: 320, height: 400)
    popover.behavior = .transient
    popover.delegate = self
    popover.contentViewController = NSHostingController(
        rootView: MenuBarPopover(
            appState: appState,
            onShowOnboarding: onShowOnboarding,
            onOpenedSettings: { [weak self] in
                self?.popover?.performClose(nil)
            }
        )
    )

    self.statusItem = statusItem
    self.popover = popover
}
```

Remove `import Sparkle` from `MenuBarManager.swift`.

- [ ] **Step 3: Update the AppDelegate setup call and drop the AppState passthrough**

In `Dict-app/Dict_appApp.swift`:

```swift
menuBarManager.setup(appState: appState) { [weak self] in
    guard let self else { return }
    self.onboardingController.show(appState: self.appState)
}
```

In `Dict-app/AppState.swift`, delete the `isFormattingEnabled` computed passthrough property (the Settings window binds `settings.isFormattingEnabled` directly and nothing else uses it).

- [ ] **Step 4: Build**

Run: `xcodebuild build -project Dict-app.xcodeproj -scheme Dict-app -destination 'platform=macOS' -quiet`
Expected: build succeeds with no references to the removed passthrough or updater param.

- [ ] **Step 5: Commit**

```bash
git add Dict-app/MenuBarPopover.swift Dict-app/MenuBarManager.swift Dict-app/Dict_appApp.swift Dict-app/AppState.swift Dict-app/SettingsView.swift
git commit -m "feat: popover slims to status + history + quick mute with Settings… button"
```

---

### Task 9: Full test pass + manual verification

**Files:** none (verification only)

- [ ] **Step 1: Run the whole unit suite (excluding the model-downloading end-to-end tests)**

Run: `xcodebuild test -project Dict-app.xcodeproj -scheme Dict-app -destination 'platform=macOS' -skip-testing:Dict-appTests/EndToEndTranscriptionTests -quiet`
Expected: PASS — SettingsStoreTests, DictationKeyLogicTests, HistoryStoreTests, plus the pre-existing VoiceGate/TranscriptFilter/TranscriptFormatter suites.

- [ ] **Step 2: Release-style build**

Run: `xcodebuild build -project Dict-app.xcodeproj -scheme Dict-app -destination 'platform=macOS' -quiet`
Expected: build succeeds, no warnings introduced in changed files.

- [ ] **Step 3: Manual verification checklist (run the app)**

Launch the built app (quit any running copy first) and verify:

1. Menu bar popover shows: Dictation Enabled, history, Settings…, Quit — no Format Transcripts toggle, no Check for Updates.
2. Settings… opens the tabbed window **while another app is frontmost** (the LSUIElement quirk — if it doesn't open, apply the `showSettingsWindow:` fallback from Task 8 Step 1 and re-verify).
3. General tab: toggling Launch at Login flips the entry in System Settings > General > Login Items; hotkey picker switches the trigger key with immediate effect; activation mode "Press to start and stop" starts on first press, stops and inserts on second; Format transcripts toggle still controls formatting.
4. Hold mode still behaves exactly as before: hold-speak-release inserts; sub-150 ms tap cancels; Space while holding goes hands-free.
5. Changing the hotkey while recording stops the recording cleanly (transcript inserted, HUD dismissed).
6. History tab: setting "Keep history" to Last 10 immediately prunes the popover list; Off stops new entries appearing; Clear History empties the list after confirmation.
7. About tab: correct version/build, Check for Updates… runs Sparkle.
8. Quit and relaunch: all settings persist; a pre-existing "Format Transcripts = off" choice from an earlier build is respected.

- [ ] **Step 4: Final commit (if any fixups were needed during verification)**

```bash
git add -A
git commit -m "fix: settings verification fixups"
```
