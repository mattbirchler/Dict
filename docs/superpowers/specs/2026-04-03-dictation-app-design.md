# Dictation App — Design Spec

## Overview

A menu bar-only macOS app that lets users hold a right modifier key to dictate text. Audio is transcribed on-device, cleaned up with Apple Foundation Models, and pasted at the cursor. No Dock icon, no main window, no network calls.

**Platform:** macOS Tahoe, unsandboxed  
**Architecture:** SwiftUI + AppKit hybrid (SwiftUI for popover/onboarding UI, AppKit for non-activating HUD panel and CGEvent tap)  
**Storage:** SwiftData for history

---

## App Structure & Lifecycle

### Entry Point

- `Dict_appApp.swift` — `@main`, sets up `NSStatusItem`, owns `AppState`
- `LSUIElement = true` in Info.plist (no Dock icon)

### Core State

- `AppState.swift` — Observable object holding: recording state, enabled/disabled toggle, permission statuses, references to subsystems. Central coordinator.

### Lifecycle

1. Launch → check permissions → show onboarding if first launch or missing permissions
2. Install CGEvent tap for key monitoring
3. Idle in menu bar until key press
4. Key held ≥ 0.3s → record → transcribe → AI cleanup → paste

---

## Key Monitoring

### `KeyMonitor.swift`

- CGEvent tap (`.cgSessionEventTap`) monitoring `.flagsChanged` events
- Distinguishes right vs. left modifiers via `CGEventFlags` bitmask and keycodes (right Command = keycode 54, right Control = keycode 62)
- Installed when dictation toggle is enabled, removed when disabled

### Tap-vs-Hold Logic

1. **Key down** → schedule "start recording" after 0.3s via `DispatchWorkItem`
2. **Key up before 0.3s** → cancel scheduled start, do nothing (normal modifier tap)
3. **Key still held at 0.3s** → start recording, show HUD
4. **Key up after recording started** → stop recording, begin transcription pipeline

---

## Recording & Transcription Pipeline

### `AudioRecorder.swift`

- Wraps `AVAudioEngine`
- Captures from default input device
- Exposes real-time RMS audio levels for waveform HUD
- Provides current input device name for HUD display
- Records to temporary file

### `TranscriptionService.swift`

- Wraps `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true`
- Takes temp audio file, returns raw transcript string
- Deletes temp file immediately after transcription

### `AICleanupService.swift`

- Wraps Apple Foundation Models framework
- System prompt: "You are a transcription cleanup assistant. Fix punctuation, capitalization, and remove filler words. Do not change the meaning, tone, or vocabulary. Return only the cleaned text with no commentary."
- If Foundation Models unavailable (older hardware): returns raw transcript as-is, surfaces note via AppState

### `TextInsertionService.swift`

- Saves previous pasteboard contents (all types via `NSPasteboard.PasteboardItem`) before overwriting
- Copies cleaned text to `NSPasteboard.general`
- Simulates Cmd+V via `CGEvent`
- After 0.5s delay, restores previous pasteboard contents (preserving rich text, images, etc.)

### `PipelineCoordinator.swift`

- Orchestrates: AudioRecorder → TranscriptionService → AICleanupService → HistoryStore → TextInsertionService
- Called by AppState when recording stops
- Runs off main thread via async/await
- Handles errors at each stage, surfaces via AppState

---

## Data & History

### `TranscriptionEntry.swift` (SwiftData @Model)

- `id: UUID`
- `cleanedText: String`
- `timestamp: Date`

### `HistoryStore.swift`

- Manages SwiftData model container
- Save new entry, fetch recent entries (sorted by timestamp descending)
- Prunes beyond 50 entries on each save (FIFO)

---

## UI Components

### `MenuBarManager.swift`

- Manages `NSStatusItem` with microphone/waveform system image
- Hosts `NSPopover` containing SwiftUI popover view

### `MenuBarPopover.swift` (SwiftUI)

- Enable/disable toggle at top
- Permission warning banner (if any permission missing, tappable to re-open onboarding)
- List of recent transcriptions: truncated text, timestamp, copy button per entry
- Quit button at bottom
- Standard SwiftUI List, native controls, functional and clean styling

### `WaveformHUD.swift` (SwiftUI) + `HUDPanelController.swift`

- **Design: Compact Pill** — translucent rounded-rect with:
  - Pulsing red recording dot
  - Animated audio level bars driven by real-time RMS values
  - Mic device name as secondary text
- Hosted in `NSPanel` (`.nonactivatingPanel`, `.floating` level)
- Positioned bottom-center of main screen
- `HUDPanelController` manages show/dismiss with fade animation
- Does not steal focus from current app

### `OnboardingWindow.swift` (SwiftUI via NSWindow)

Shown on first launch. Three steps, one per permission:

1. **Microphone** — explanation + button to open System Settings > Privacy > Microphone
2. **Accessibility** — explanation + button to open System Settings > Privacy > Accessibility
3. **Speech Recognition** — explanation + button to open System Settings > Privacy > Speech Recognition

Each step shows checkmark when granted. "Get Started" button dismisses. First-launch tracked via UserDefaults.

### `PermissionChecker.swift`

- Checks: `AVCaptureDevice.authorizationStatus`, `AXIsProcessTrusted()`, `SFSpeechRecognizer.authorizationStatus`
- Published properties on AppState so views react to changes
- Checked on launch and periodically

---

## File Structure

```
Dict-app/
├── Dict_appApp.swift          # @main entry point
├── AppState.swift             # Central observable state
├── KeyMonitor.swift           # CGEvent tap for right modifier keys
├── AudioRecorder.swift        # AVAudioEngine recording
├── TranscriptionService.swift # SFSpeechRecognizer wrapper
├── AICleanupService.swift     # Foundation Models cleanup
├── TextInsertionService.swift # Pasteboard + Cmd+V simulation
├── PipelineCoordinator.swift  # Orchestrates the full flow
├── HistoryStore.swift         # SwiftData CRUD + pruning
├── TranscriptionEntry.swift   # SwiftData model
├── MenuBarManager.swift       # NSStatusItem + NSPopover
├── MenuBarPopover.swift       # SwiftUI popover content
├── WaveformHUD.swift          # SwiftUI waveform pill view
├── HUDPanelController.swift   # NSPanel management
├── OnboardingWindow.swift     # First-launch permission setup
├── PermissionChecker.swift    # Permission status checking
└── Assets.xcassets/           # App icon, colors
```

---

## Permissions

| Permission | API | Reason |
|---|---|---|
| Microphone | `AVCaptureDevice` | Audio capture |
| Accessibility | `AXIsProcessTrusted()` | Global key monitoring + paste simulation |
| Speech Recognition | `SFSpeechRecognizer` | On-device transcription |

---

## Error Handling

- **Foundation Models unavailable:** Fall back to raw transcript, show note in menu bar popover
- **Transcription fails:** Show error in menu bar popover, discard audio
- **Permission revoked:** Show warning banner in popover, disable dictation toggle
- **CGEvent tap fails to install:** Surface as Accessibility permission issue
- **No microphone available:** Show error when recording attempted

---

## Non-Goals (v1)

- No App Store / sandboxing
- No cloud/network calls
- No multi-language support (system locale only)
- No configurable key bindings
- No audio persistence or export
- No iPhone/iPad
