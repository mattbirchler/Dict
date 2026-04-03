# Dictation App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a menu bar-only macOS dictation app that captures audio on right-modifier key hold, transcribes with SFSpeechRecognizer, cleans up with Foundation Models, and pastes at cursor.

**Architecture:** SwiftUI + AppKit hybrid. SwiftUI for popover/onboarding UI, AppKit NSPanel for non-activating waveform HUD, CGEvent tap for key monitoring. SwiftData for history. All on-device, unsandboxed.

**Tech Stack:** Swift, SwiftUI, AppKit, AVAudioEngine, Speech framework, FoundationModels framework, SwiftData, CGEvent API

**Important Notes:**
- The project uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` — all types default to `@MainActor`. Mark things `nonisolated` only when needed (C callbacks, audio tap closures).
- The Xcode project uses `PBXFileSystemSynchronizedRootGroup` — any `.swift` file placed in `Dict-app/Dict-app/` is automatically compiled. No pbxproj edits needed for new source files.
- Build command: `xcodebuild -project Dict-app.xcodeproj -scheme Dict-app -configuration Debug build 2>&1 | tail -20`
- Run from project root: `/Users/matt/Apps/Dict-app`

---

### Task 1: Project Configuration

**Files:**
- Modify: `Dict-app.xcodeproj/project.pbxproj`
- Delete: `Dict-app/Dict-app/ContentView.swift`
- Delete: `Dict-app/Dict-app/Item.swift`

- [ ] **Step 1: Disable App Sandbox and add Info.plist keys**

In `Dict-app.xcodeproj/project.pbxproj`, find BOTH target-level `XCBuildConfiguration` sections (Debug at line ~248 and Release at line ~280). In each, make these changes:

Change `ENABLE_APP_SANDBOX = YES;` to `ENABLE_APP_SANDBOX = NO;`

Add these keys to both configurations (inside the `buildSettings` dict):

```
INFOPLIST_KEY_LSUIElement = YES;
INFOPLIST_KEY_NSMicrophoneUsageDescription = "Dict needs microphone access to record your voice for dictation.";
INFOPLIST_KEY_NSSpeechRecognitionUsageDescription = "Dict uses on-device speech recognition to transcribe your dictation.";
```

- [ ] **Step 2: Delete template files**

```bash
rm Dict-app/Dict-app/ContentView.swift
rm Dict-app/Dict-app/Item.swift
```

- [ ] **Step 3: Create minimal app entry point stub**

Write `Dict-app/Dict-app/Dict_appApp.swift` with a minimal compilable stub (we'll flesh it out in Task 13):

```swift
import SwiftUI

@main
struct Dict_appApp: App {
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
```

- [ ] **Step 4: Verify build**

```bash
cd /Users/matt/Apps/Dict-app && xcodebuild -project Dict-app.xcodeproj -scheme Dict-app -configuration Debug build 2>&1 | tail -20
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "chore: configure project for menu bar app (disable sandbox, add LSUIElement, remove template files)"
```

---

### Task 2: Data Model & History Store

**Files:**
- Create: `Dict-app/Dict-app/TranscriptionEntry.swift`
- Create: `Dict-app/Dict-app/HistoryStore.swift`

- [ ] **Step 1: Create TranscriptionEntry SwiftData model**

Write `Dict-app/Dict-app/TranscriptionEntry.swift`:

```swift
import Foundation
import SwiftData

@Model
final class TranscriptionEntry {
    var id: UUID
    var cleanedText: String
    var timestamp: Date

    init(cleanedText: String, timestamp: Date = Date()) {
        self.id = UUID()
        self.cleanedText = cleanedText
        self.timestamp = timestamp
    }
}
```

- [ ] **Step 2: Create HistoryStore**

Write `Dict-app/Dict-app/HistoryStore.swift`:

```swift
import Foundation
import SwiftData

@Observable
final class HistoryStore {
    private let container: ModelContainer
    private let maxEntries = 50

    var recentEntries: [TranscriptionEntry] = []

    init() {
        let schema = Schema([TranscriptionEntry.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            self.container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        fetchEntries()
    }

    @MainActor
    func save(cleanedText: String) {
        let context = container.mainContext
        let entry = TranscriptionEntry(cleanedText: cleanedText)
        context.insert(entry)
        pruneOldEntries(context: context)
        try? context.save()
        fetchEntries()
    }

    @MainActor
    func fetchEntries() {
        let context = container.mainContext
        let descriptor = FetchDescriptor<TranscriptionEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        recentEntries = (try? context.fetch(descriptor)) ?? []
    }

    @MainActor
    private func pruneOldEntries(context: ModelContext) {
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

- [ ] **Step 3: Verify build**

```bash
cd /Users/matt/Apps/Dict-app && xcodebuild -project Dict-app.xcodeproj -scheme Dict-app -configuration Debug build 2>&1 | tail -20
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: add TranscriptionEntry model and HistoryStore with 50-entry pruning"
```

---

### Task 3: Permission Checker

**Files:**
- Create: `Dict-app/Dict-app/PermissionChecker.swift`

- [ ] **Step 1: Create PermissionChecker**

Write `Dict-app/Dict-app/PermissionChecker.swift`:

```swift
import AVFoundation
import Speech

@Observable
final class PermissionChecker {
    var microphoneGranted = false
    var accessibilityGranted = false
    var speechRecognitionGranted = false

    var allGranted: Bool {
        microphoneGranted && accessibilityGranted && speechRecognitionGranted
    }

    func checkAll() {
        checkMicrophone()
        checkAccessibility()
        checkSpeechRecognition()
    }

    func checkMicrophone() {
        microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    func checkAccessibility() {
        accessibilityGranted = AXIsProcessTrusted()
    }

    func checkSpeechRecognition() {
        speechRecognitionGranted = SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    func requestMicrophone() async {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        microphoneGranted = granted
    }

    func requestSpeechRecognition() async {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                Task { @MainActor in
                    self.speechRecognitionGranted = (status == .authorized)
                    continuation.resume()
                }
            }
        }
    }

    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    func openMicrophoneSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        NSWorkspace.shared.open(url)
    }

    func openSpeechRecognitionSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")!
        NSWorkspace.shared.open(url)
    }
}
```

- [ ] **Step 2: Verify build**

```bash
cd /Users/matt/Apps/Dict-app && xcodebuild -project Dict-app.xcodeproj -scheme Dict-app -configuration Debug build 2>&1 | tail -20
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: add PermissionChecker for microphone, accessibility, and speech recognition"
```

---

### Task 4: Audio Recorder

**Files:**
- Create: `Dict-app/Dict-app/AudioRecorder.swift`

- [ ] **Step 1: Create AudioRecorder**

Write `Dict-app/Dict-app/AudioRecorder.swift`. Uses CoreAudio for macOS mic name lookup (AVAudioSession is iOS-only):

```swift
import AVFoundation
import CoreAudio

@Observable
final class AudioRecorder {
    private var engine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var tempFileURL: URL?

    var currentLevel: Float = 0
    var isRecording = false

    var inputDeviceName: String {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0, nil,
            &size, &deviceID
        )
        guard status == noErr else { return "Unknown Microphone" }

        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var nameSize = UInt32(MemoryLayout<CFString>.size)
        let nameStatus = AudioObjectGetPropertyData(
            deviceID,
            &nameAddress,
            0, nil,
            &nameSize, &name
        )
        guard nameStatus == noErr else { return "Unknown Microphone" }
        return name as String
    }

    func startRecording() throws -> URL {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent(UUID().uuidString + ".caf")

        let audioFile = try AVAudioFile(forWriting: url, settings: format.settings)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            try? audioFile.write(from: buffer)
            let level = Self.computeRMS(buffer: buffer)
            Task { @MainActor [weak self] in
                self?.currentLevel = level
            }
        }

        engine.prepare()
        try engine.start()

        self.engine = engine
        self.audioFile = audioFile
        self.tempFileURL = url
        self.isRecording = true

        return url
    }

    func stopRecording() -> URL? {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        audioFile = nil
        isRecording = false
        currentLevel = 0

        let url = tempFileURL
        tempFileURL = nil
        return url
    }

    nonisolated private static func computeRMS(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }

        var sum: Float = 0
        for i in 0..<frames {
            let sample = channelData[0][i]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frames))
        return min(rms * 5, 1.0)
    }
}
```

- [ ] **Step 2: Verify build**

```bash
cd /Users/matt/Apps/Dict-app && xcodebuild -project Dict-app.xcodeproj -scheme Dict-app -configuration Debug build 2>&1 | tail -20
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: add AudioRecorder with AVAudioEngine capture and real-time RMS levels"
```

---

### Task 5: Transcription Service

**Files:**
- Create: `Dict-app/Dict-app/TranscriptionService.swift`

- [ ] **Step 1: Create TranscriptionService**

Write `Dict-app/Dict-app/TranscriptionService.swift`:

```swift
import Speech

final class TranscriptionService {
    private let recognizer: SFSpeechRecognizer?

    init() {
        self.recognizer = SFSpeechRecognizer()
        self.recognizer?.supportsOnDeviceRecognition = true
    }

    func transcribe(audioURL: URL) async throws -> String {
        guard let recognizer, recognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false

        let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<SFSpeechRecognitionResult, Error>) in
            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if let result, result.isFinal {
                    continuation.resume(returning: result)
                }
            }
        }

        // Delete temp audio file immediately
        try? FileManager.default.removeItem(at: audioURL)

        return result.bestTranscription.formattedString
    }
}

enum TranscriptionError: LocalizedError {
    case recognizerUnavailable

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return "Speech recognition is not available on this device."
        }
    }
}
```

- [ ] **Step 2: Verify build**

```bash
cd /Users/matt/Apps/Dict-app && xcodebuild -project Dict-app.xcodeproj -scheme Dict-app -configuration Debug build 2>&1 | tail -20
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: add TranscriptionService with on-device SFSpeechRecognizer"
```

---

### Task 6: AI Cleanup Service

**Files:**
- Create: `Dict-app/Dict-app/AICleanupService.swift`

- [ ] **Step 1: Create AICleanupService**

Write `Dict-app/Dict-app/AICleanupService.swift`:

```swift
import FoundationModels

final class AICleanupService {
    private let systemPrompt = """
        You are a transcription cleanup assistant. Fix punctuation, capitalization, \
        and remove filler words (um, uh, like, you know). Do not change the meaning, \
        tone, or vocabulary. Return only the cleaned text with no commentary.
        """

    var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    func cleanup(rawTranscript: String) async throws -> String {
        guard isAvailable else {
            return rawTranscript
        }

        let session = LanguageModelSession(instructions: systemPrompt)
        let response = try await session.respond(to: rawTranscript)
        return response.content
    }
}
```

- [ ] **Step 2: Verify build**

```bash
cd /Users/matt/Apps/Dict-app && xcodebuild -project Dict-app.xcodeproj -scheme Dict-app -configuration Debug build 2>&1 | tail -20
```

Expected: `BUILD SUCCEEDED`. If FoundationModels framework is not available in the current SDK, wrap with `#if canImport(FoundationModels)` and provide a fallback that returns the raw transcript. Check the error output and adjust accordingly.

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: add AICleanupService with Foundation Models for transcript cleanup"
```

---

### Task 7: Text Insertion Service

**Files:**
- Create: `Dict-app/Dict-app/TextInsertionService.swift`

- [ ] **Step 1: Create TextInsertionService**

Write `Dict-app/Dict-app/TextInsertionService.swift`:

```swift
import AppKit
import CoreGraphics

final class TextInsertionService {
    func insertText(_ text: String) async {
        let pasteboard = NSPasteboard.general
        let previousContents = savePasteboard(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        simulatePaste()

        // Wait then restore previous clipboard
        try? await Task.sleep(for: .milliseconds(500))
        restorePasteboard(pasteboard, items: previousContents)
    }

    private func savePasteboard(_ pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        var saved: [[NSPasteboard.PasteboardType: Data]] = []
        guard let items = pasteboard.pasteboardItems else { return saved }
        for item in items {
            var itemData: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    itemData[type] = data
                }
            }
            saved.append(itemData)
        }
        return saved
    }

    private func restorePasteboard(_ pasteboard: NSPasteboard, items: [[NSPasteboard.PasteboardType: Data]]) {
        guard !items.isEmpty else { return }
        pasteboard.clearContents()
        var pasteboardItems: [NSPasteboardItem] = []
        for itemData in items {
            let item = NSPasteboardItem()
            for (type, data) in itemData {
                item.setData(data, forType: type)
            }
            pasteboardItems.append(item)
        }
        pasteboard.writeObjects(pasteboardItems)
    }

    private func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) // 0x09 = V
        keyDown?.flags = .maskCommand

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cgAnnotatedSessionEventTap)
        keyUp?.post(tap: .cgAnnotatedSessionEventTap)
    }
}
```

- [ ] **Step 2: Verify build**

```bash
cd /Users/matt/Apps/Dict-app && xcodebuild -project Dict-app.xcodeproj -scheme Dict-app -configuration Debug build 2>&1 | tail -20
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: add TextInsertionService with clipboard save/restore and Cmd+V simulation"
```

---

### Task 8: AppState & PipelineCoordinator

**Files:**
- Create: `Dict-app/Dict-app/AppState.swift`
- Create: `Dict-app/Dict-app/PipelineCoordinator.swift`

Dependencies: Tasks 2, 3, 4, 5, 6, 7

- [ ] **Step 1: Create PipelineCoordinator**

Write `Dict-app/Dict-app/PipelineCoordinator.swift`:

```swift
import Foundation

final class PipelineCoordinator {
    let audioRecorder = AudioRecorder()
    let transcriptionService = TranscriptionService()
    let aiCleanupService = AICleanupService()
    let textInsertionService = TextInsertionService()
    let historyStore = HistoryStore()

    private var currentAudioURL: URL?

    func startRecording() {
        do {
            currentAudioURL = try audioRecorder.startRecording()
        } catch {
            print("Failed to start recording: \(error)")
        }
    }

    func stopRecordingAndProcess() async -> String? {
        guard let audioURL = audioRecorder.stopRecording() else {
            return nil
        }

        do {
            let rawTranscript = try await transcriptionService.transcribe(audioURL: audioURL)
            guard !rawTranscript.isEmpty else { return nil }

            let cleanedText: String
            if aiCleanupService.isAvailable {
                cleanedText = try await aiCleanupService.cleanup(rawTranscript: rawTranscript)
            } else {
                cleanedText = rawTranscript
            }

            historyStore.save(cleanedText: cleanedText)
            await textInsertionService.insertText(cleanedText)

            return cleanedText
        } catch {
            print("Pipeline error: \(error)")
            // Clean up audio file if transcription failed
            try? FileManager.default.removeItem(at: audioURL)
            return nil
        }
    }
}
```

- [ ] **Step 2: Create AppState**

Write `Dict-app/Dict-app/AppState.swift`:

```swift
import Foundation

@Observable
final class AppState {
    let permissionChecker = PermissionChecker()
    let pipeline = PipelineCoordinator()

    var isEnabled = true
    var isRecording = false
    var isProcessing = false
    var lastError: String?
    var foundationModelsAvailable: Bool { pipeline.aiCleanupService.isAvailable }
    var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") }
        set { UserDefaults.standard.set(newValue, forKey: "hasCompletedOnboarding") }
    }

    func startRecording() {
        guard isEnabled, !isRecording, !isProcessing else { return }
        isRecording = true
        lastError = nil
        pipeline.startRecording()
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        isProcessing = true

        Task {
            let result = await pipeline.stopRecordingAndProcess()
            isProcessing = false
            if result == nil {
                lastError = "Transcription failed. Please try again."
            }
        }
    }
}
```

- [ ] **Step 3: Verify build**

```bash
cd /Users/matt/Apps/Dict-app && xcodebuild -project Dict-app.xcodeproj -scheme Dict-app -configuration Debug build 2>&1 | tail -20
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: add AppState and PipelineCoordinator to orchestrate recording pipeline"
```

---

### Task 9: Key Monitor

**Files:**
- Create: `Dict-app/Dict-app/KeyMonitor.swift`

Dependencies: Task 8

- [ ] **Step 1: Create KeyMonitor**

Write `Dict-app/Dict-app/KeyMonitor.swift`:

```swift
import CoreGraphics
import Foundation

final class KeyMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var delayedStartWork: DispatchWorkItem?
    private var isKeyHeld = false
    private var recordingStarted = false

    var onRecordingStart: (() -> Void)?
    var onRecordingStop: (() -> Void)?

    private static let rightCommandKeycode: Int64 = 54
    private static let rightControlKeycode: Int64 = 62
    private static let holdThreshold: TimeInterval = 0.3

    func install() -> Bool {
        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)

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
        delayedStartWork?.cancel()
        delayedStartWork = nil
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        eventTap = nil
        runLoopSource = nil
        isKeyHeld = false
        recordingStarted = false
    }

    nonisolated private static let eventCallback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passRetained(event) }
        let monitor = Unmanaged<KeyMonitor>.fromOpaque(refcon).takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = monitor.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keycode == rightCommandKeycode || keycode == rightControlKeycode else {
            return Unmanaged.passRetained(event)
        }

        let flags = event.flags

        let isRightCommandDown = keycode == rightCommandKeycode &&
            flags.contains(.maskCommand)
        let isRightControlDown = keycode == rightControlKeycode &&
            flags.contains(.maskControl)
        let isDown = isRightCommandDown || isRightControlDown

        Task { @MainActor in
            if isDown && !monitor.isKeyHeld {
                monitor.handleKeyDown()
            } else if !isDown && monitor.isKeyHeld {
                monitor.handleKeyUp()
            }
        }

        return Unmanaged.passRetained(event)
    }

    private func handleKeyDown() {
        isKeyHeld = true
        recordingStarted = false

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isKeyHeld else { return }
            self.recordingStarted = true
            self.onRecordingStart?()
        }
        delayedStartWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdThreshold, execute: work)
    }

    private func handleKeyUp() {
        isKeyHeld = false
        delayedStartWork?.cancel()
        delayedStartWork = nil

        if recordingStarted {
            recordingStarted = false
            onRecordingStop?()
        }
    }
}
```

- [ ] **Step 2: Verify build**

```bash
cd /Users/matt/Apps/Dict-app && xcodebuild -project Dict-app.xcodeproj -scheme Dict-app -configuration Debug build 2>&1 | tail -20
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: add KeyMonitor with CGEvent tap for right Command/Control detection"
```

---

### Task 10: Waveform HUD

**Files:**
- Create: `Dict-app/Dict-app/WaveformHUD.swift`
- Create: `Dict-app/Dict-app/HUDPanelController.swift`

Dependencies: Task 4, Task 8

- [ ] **Step 1: Create WaveformHUD SwiftUI view**

Write `Dict-app/Dict-app/WaveformHUD.swift`. Uses `TimelineView` for the pulsing recording dot:

```swift
struct WaveformHUD: View {
    var audioLevel: Float
    var micName: String

    private let barCount = 7
    private let barWidth: CGFloat = 3
    private let maxBarHeight: CGFloat = 24
    private let minBarHeight: CGFloat = 4

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05)) { timeline in
            let pulse = (sin(timeline.date.timeIntervalSinceReferenceDate * 4) + 1) / 2

            HStack(spacing: 14) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
                    .shadow(color: .red.opacity(0.6), radius: 4)
                    .opacity(0.4 + pulse * 0.6)

                HStack(spacing: 3) {
                    ForEach(0..<barCount, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.green.opacity(0.85))
                            .frame(width: barWidth, height: barHeight(for: index))
                    }
                }
                .frame(height: maxBarHeight)
                .animation(.easeInOut(duration: 0.15), value: audioLevel)

                Text(micName)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: Capsule())
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let position = Double(index) / Double(barCount - 1)
        let wave = sin(position * .pi)
        let level = CGFloat(audioLevel)
        let height = minBarHeight + (maxBarHeight - minBarHeight) * level * wave
        return max(minBarHeight, height)
    }
}
```

- [ ] **Step 2: Create HUDPanelController**

Write `Dict-app/Dict-app/HUDPanelController.swift`:

```swift
import AppKit
import SwiftUI

final class HUDPanelController {
    private var panel: NSPanel?

    func show(audioLevel: @escaping () -> Float, micName: @escaping () -> String) {
        guard panel == nil else { return }

        let hostingView = NSHostingView(rootView:
            WaveformHUDContainer(audioLevel: audioLevel, micName: micName)
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 56)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 56),
            styleMask: [.nonactivatingPanel, .hudWindow, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = hostingView
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Position at bottom center of main screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 160
            let y = screenFrame.minY + 80
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 1
        }

        self.panel = panel
    }

    func dismiss() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            panel.orderOut(nil)
            self?.panel = nil
        })
    }
}

struct WaveformHUDContainer: View {
    var audioLevel: () -> Float
    var micName: () -> String

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05)) { _ in
            WaveformHUD(audioLevel: audioLevel(), micName: micName())
        }
    }
}
```

- [ ] **Step 3: Verify build**

```bash
cd /Users/matt/Apps/Dict-app && xcodebuild -project Dict-app.xcodeproj -scheme Dict-app -configuration Debug build 2>&1 | tail -20
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: add WaveformHUD compact pill and HUDPanelController"
```

---

### Task 11: Menu Bar Manager & Popover

**Files:**
- Create: `Dict-app/Dict-app/MenuBarManager.swift`
- Create: `Dict-app/Dict-app/MenuBarPopover.swift`

Dependencies: Task 2, Task 8

- [ ] **Step 1: Create MenuBarPopover SwiftUI view**

Write `Dict-app/Dict-app/MenuBarPopover.swift`:

```swift
import SwiftUI

struct MenuBarPopover: View {
    @Bindable var appState: AppState
    var onShowOnboarding: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Enable/disable toggle
            Toggle("Dictation Enabled", isOn: $appState.isEnabled)
                .toggleStyle(.switch)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider()

            // Permission warning
            if !appState.permissionChecker.allGranted {
                Button(action: onShowOnboarding) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text("Missing permissions — click to fix")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.yellow.opacity(0.1))
                }
                .buttonStyle(.plain)

                Divider()
            }

            // Foundation Models warning
            if !appState.foundationModelsAvailable {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text("AI cleanup unavailable — using raw transcription")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                Divider()
            }

            // Status
            if appState.isProcessing {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Processing…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                Divider()
            }

            if let error = appState.lastError {
                HStack {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                Divider()
            }

            // History
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if appState.pipeline.historyStore.recentEntries.isEmpty {
                        Text("No transcriptions yet")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                    } else {
                        ForEach(appState.pipeline.historyStore.recentEntries) { entry in
                            HistoryEntryRow(entry: entry)
                            Divider().padding(.leading, 16)
                        }
                    }
                }
            }
            .frame(maxHeight: 300)

            Divider()

            // Quit
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

struct HistoryEntryRow: View {
    let entry: TranscriptionEntry

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.cleanedText)
                    .lineLimit(3)
                    .font(.body)
                Text(entry.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.cleanedText, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Copy to clipboard")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
```

- [ ] **Step 2: Create MenuBarManager**

Write `Dict-app/Dict-app/MenuBarManager.swift`:

```swift
import AppKit
import SwiftUI

final class MenuBarManager {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var eventMonitor: Any?

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
        popover.contentViewController = NSHostingController(
            rootView: MenuBarPopover(appState: appState, onShowOnboarding: onShowOnboarding)
        )

        self.statusItem = statusItem
        self.popover = popover
    }

    @objc private func togglePopover() {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

            // Close popover when clicking outside
            eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.popover?.performClose(nil)
            }
        }
    }

    func closePopover() {
        popover?.performClose(nil)
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}
```

- [ ] **Step 3: Verify build**

```bash
cd /Users/matt/Apps/Dict-app && xcodebuild -project Dict-app.xcodeproj -scheme Dict-app -configuration Debug build 2>&1 | tail -20
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: add MenuBarManager and MenuBarPopover with history list"
```

---

### Task 12: Onboarding Window

**Files:**
- Create: `Dict-app/Dict-app/OnboardingWindow.swift`

Dependencies: Task 3, Task 8

- [ ] **Step 1: Create OnboardingWindow**

Write `Dict-app/Dict-app/OnboardingWindow.swift`:

```swift
import SwiftUI

struct OnboardingView: View {
    @Bindable var appState: AppState
    var onComplete: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text("Welcome to Dict")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Dict needs a few permissions to work. Grant each one below.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 16) {
                PermissionRow(
                    title: "Microphone",
                    description: "Record your voice for dictation",
                    systemImage: "mic.fill",
                    isGranted: appState.permissionChecker.microphoneGranted,
                    action: {
                        Task { await appState.permissionChecker.requestMicrophone() }
                    },
                    openSettings: appState.permissionChecker.openMicrophoneSettings
                )

                PermissionRow(
                    title: "Accessibility",
                    description: "Detect key presses and paste text globally",
                    systemImage: "hand.raised.fill",
                    isGranted: appState.permissionChecker.accessibilityGranted,
                    action: appState.permissionChecker.openAccessibilitySettings,
                    openSettings: appState.permissionChecker.openAccessibilitySettings
                )

                PermissionRow(
                    title: "Speech Recognition",
                    description: "Transcribe your voice on-device",
                    systemImage: "waveform.badge.mic",
                    isGranted: appState.permissionChecker.speechRecognitionGranted,
                    action: {
                        Task { await appState.permissionChecker.requestSpeechRecognition() }
                    },
                    openSettings: appState.permissionChecker.openSpeechRecognitionSettings
                )
            }
            .padding(.horizontal)

            Spacer()

            Button("Get Started") {
                appState.hasCompletedOnboarding = true
                onComplete()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!appState.permissionChecker.allGranted)

            if !appState.permissionChecker.allGranted {
                Text("Grant all permissions to continue")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(32)
        .frame(width: 480, height: 520)
        .onAppear {
            appState.permissionChecker.checkAll()
        }
    }
}

struct PermissionRow: View {
    let title: String
    let description: String
    let systemImage: String
    let isGranted: Bool
    let action: () -> Void
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(isGranted ? .green : .secondary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title2)
            } else {
                Button("Grant") {
                    action()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isGranted ? Color.green.opacity(0.05) : Color.secondary.opacity(0.05))
        )
    }
}

final class OnboardingWindowController {
    private var window: NSWindow?

    func show(appState: AppState) {
        guard window == nil else {
            window?.makeKeyAndOrderFront(nil)
            return
        }

        let onboardingView = OnboardingView(appState: appState) { [weak self] in
            self?.close()
        }

        let hostingController = NSHostingController(rootView: onboardingView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Dict Setup"
        window.styleMask = [.titled, .closable]
        window.center()
        window.makeKeyAndOrderFront(nil)

        // Bring app to front for onboarding
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }

    func close() {
        window?.close()
        window = nil
    }
}
```

- [ ] **Step 2: Verify build**

```bash
cd /Users/matt/Apps/Dict-app && xcodebuild -project Dict-app.xcodeproj -scheme Dict-app -configuration Debug build 2>&1 | tail -20
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: add OnboardingWindow with permission setup flow"
```

---

### Task 13: Final App Entry Point & Wiring

**Files:**
- Modify: `Dict-app/Dict-app/Dict_appApp.swift`

Dependencies: All previous tasks

- [ ] **Step 1: Write the full app entry point**

Replace `Dict-app/Dict-app/Dict_appApp.swift` with this `NSApplicationDelegateAdaptor` version (using the App struct's init for setup doesn't work well with `@State`):

```swift
import SwiftUI

@main
struct Dict_appApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    let menuBarManager = MenuBarManager()
    let hudController = HUDPanelController()
    let keyMonitor = KeyMonitor()
    let onboardingController = OnboardingWindowController()
    private var permissionCheckTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        appState.permissionChecker.checkAll()

        menuBarManager.setup(appState: appState) { [weak self] in
            guard let self else { return }
            self.onboardingController.show(appState: self.appState)
        }

        keyMonitor.onRecordingStart = { [weak self] in
            guard let self else { return }
            self.appState.startRecording()
            self.hudController.show(
                audioLevel: { [weak self] in self?.appState.pipeline.audioRecorder.currentLevel ?? 0 },
                micName: { [weak self] in self?.appState.pipeline.audioRecorder.inputDeviceName ?? "Unknown" }
            )
        }

        keyMonitor.onRecordingStop = { [weak self] in
            guard let self else { return }
            self.hudController.dismiss()
            self.appState.stopRecording()
        }

        if appState.permissionChecker.accessibilityGranted {
            _ = keyMonitor.install()
        }

        if !appState.hasCompletedOnboarding {
            onboardingController.show(appState: appState)
        }

        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let wasGranted = self.appState.permissionChecker.accessibilityGranted
            self.appState.permissionChecker.checkAll()
            if !wasGranted && self.appState.permissionChecker.accessibilityGranted {
                _ = self.keyMonitor.install()
            }
        }
    }
}
```

- [ ] **Step 2: Verify build**

```bash
cd /Users/matt/Apps/Dict-app && xcodebuild -project Dict-app.xcodeproj -scheme Dict-app -configuration Debug build 2>&1 | tail -20
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: wire up app entry point with AppDelegate, key monitor, HUD, and menu bar"
```

---

## Task Dependency Graph

```
Task 1 (Project Config)
  ├── Task 2 (Data Model) ─────────────┐
  ├── Task 3 (Permissions) ────────────┤
  ├── Task 4 (Audio Recorder) ─────────┤
  ├── Task 5 (Transcription) ──────────┼── Task 8 (AppState + Pipeline)
  ├── Task 6 (AI Cleanup) ─────────────┤      ├── Task 9 (Key Monitor)
  └── Task 7 (Text Insertion) ─────────┘      ├── Task 10 (Waveform HUD)
                                               ├── Task 11 (Menu Bar)
                                               ├── Task 12 (Onboarding)
                                               └── Task 13 (Final Wiring)
```

Tasks 2-7 can run in parallel. Task 8 depends on 2-7. Tasks 9-12 depend on 8 and can run in parallel. Task 13 depends on everything.
