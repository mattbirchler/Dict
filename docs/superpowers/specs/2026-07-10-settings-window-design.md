# Settings Window Design

**Date:** 2026-07-10
**Status:** Approved

## Goal

Replace the empty `Settings` scene with a real tabbed Settings window, and add
the core preferences it exposes: launch at login, a dictation hotkey picker,
an activation-mode picker (hold vs. toggle), and history retention controls.
The menu bar popover slims down to status + history + quick mute.

## Scope

In scope:

- Tabbed Settings window (General / History / About) via the SwiftUI
  `Settings` scene.
- New `SettingsStore` observable owning all persisted preferences.
- Launch at Login (SMAppService).
- Configurable dictation hotkey: Right ⌘, Right ⌃, Right ⌥, or Fn/Globe
  (single choice; default Right ⌘).
- Activation mode: press-and-hold (today's behavior, incl. Space hands-free)
  or press-to-toggle.
- History retention: Off / Last 10 / Last 50 / Last 200 / Unlimited, plus
  Clear History.
- Popover cleanup: Format Transcripts and Check for Updates move into
  Settings; a Settings… button is added.

Out of scope (future projects): custom vocabulary, model/language pickers,
sounds, HUD options, streaming transcription, Escape-to-cancel.

## Window & tabs

The `Settings { EmptyView() }` scene in `Dict_appApp.swift` becomes a tabbed
settings window with the standard macOS settings look (native on the 26.4
target).

### General

- **Launch at Login** toggle — reads/writes `SMAppService.mainApp` directly
  (register/unregister). Not mirrored in UserDefaults; the service is the
  source of truth. If status is `.requiresApproval`, show an inline caption
  linking to System Settings > Login Items. Register/unregister failures
  surface as an inline caption, not an alert. Default: off (unregistered).
- **Dictation hotkey** picker — Right ⌘ (default), Right ⌃, Right ⌥, Fn 🌐.
  The Fn choice shows a caption noting the macOS "Press 🌐 key to…" setting
  may need to be "Do Nothing" to avoid the emoji picker.
- **Activation mode** picker — "Press and hold" (default) / "Press to start
  and stop". In hold mode a caption documents the Space hands-free trick.
- **Format Transcripts** toggle — moved from the popover, same help text.

### History

- **Keep history** picker — Off / Last 10 / Last 50 (default, matches
  today) / Last 200 / Unlimited.
- **Clear History** button — confirmation dialog, then deletes all entries.
- Caption: Off stops saving new transcriptions but does not delete existing
  ones; Clear History does that.

### About

- App icon, name, version + build (from the bundle).
- Privacy line: transcription, formatting, and history are 100% on-device;
  audio never leaves the Mac.
- **Check for Updates…** button (moves here from the popover; same
  `UpdaterViewModel` wiring).
- Acknowledgements line: WhisperKit, Sparkle.

## SettingsStore

New `@MainActor @Observable final class SettingsStore` owning every persisted
preference as a property whose `didSet` writes UserDefaults — the same
pattern `AppState.isFormattingEnabled` uses today.

Properties:

- `hotkey: HotkeyChoice` — enum `rightCommand` (default), `rightControl`,
  `rightOption`, `fn`; raw string persisted.
- `activationMode: ActivationMode` — enum `holdToTalk` (default), `toggle`;
  raw string persisted.
- `isFormattingEnabled: Bool` — migrated from AppState using the **same
  UserDefaults key** (`isFormattingEnabled`) so existing users keep their
  choice. Default true.
- `historyLimit: HistoryLimit` — enum `off`, `ten`, `fifty` (default),
  `twoHundred`, `unlimited`; raw string persisted. Exposes
  `maxEntries: Int?` (`nil` = unlimited) and `savesHistory: Bool`.

Wiring: `AppState` gains a `settings: SettingsStore` it creates and exposes;
`AppDelegate` and the Settings scene reach it through `appState`. Services
receive plain values pushed on change (as `pipeline.isFormattingEnabled` is
pushed today): AppDelegate observes settings changes and reconfigures
KeyMonitor; HistoryStore is handed the limit. `hasCompletedOnboarding` stays
on AppState; the quick-mute `isEnabled` stays runtime-only and unpersisted.

Migration note: users who previously had right ⌃ as a second hotkey lose it —
the picker is single-choice and defaults to Right ⌘. Acceptable; pre-release
app.

## KeyMonitor changes

- The hardcoded right-⌘/right-⌃ pair becomes one configurable hotkey. Each
  `HotkeyChoice` maps to a (keycode, `CGEventFlags` mask) pair: Right ⌘ = 54
  / `.maskCommand`, Right ⌃ = 62 / `.maskControl`, Right ⌥ = 61 /
  `.maskAlternate`, Fn = 63 / `.maskSecondaryFn`.
- New `activationMode`:
  - **Hold** — exactly today's behavior: record while held, releases under
    150 ms cancel as accidental taps, Space while holding switches to
    hands-free until the hotkey is pressed again.
  - **Toggle** — key-down starts recording; the next key-down stops it.
    Key-up is ignored; no hold threshold; Space is not intercepted.
- AppDelegate pushes hotkey/mode changes into the monitor. If a change
  arrives while recording, the monitor stops the recording cleanly
  (`onRecordingStop`) before reconfiguring.
- The decision logic (what a key-down/key-up/space event does in each mode
  and state) is extracted into a pure, CGEvent-free type so it can be unit
  tested.

## HistoryStore changes

- `maxEntries` (currently a hardcoded 50) becomes a settable `limit`
  reflecting `SettingsStore.historyLimit`:
  - Off → `save()` no-ops (nothing written to disk).
  - Unlimited → no pruning.
  - Numeric → prune to N. Pruning applies immediately when the setting is
    lowered, not just on the next save.
- New `clearAll()` deletes every entry and refreshes `recentEntries`.
- Failure tolerance unchanged: SwiftData errors print and leave state as-is
  (same as today's `try? context.save()`).

## Popover changes

Format Transcripts and Check for Updates move out. New layout, top to
bottom:

1. Dictation Enabled toggle (quick mute — unchanged behavior)
2. Permission warning / model download / processing / error rows (unchanged)
3. History list (unchanged)
4. **Settings…** button
5. Quit

Settings… must handle the LSUIElement quirk (`LSUIElement = YES` confirmed in
the project): activate the app first, then open the Settings scene — via
`SettingsLink` or the `openSettings` environment action, whichever proves
reliable from the popover. This is a known finicky spot; implementation
includes manual verification that it opens while another app is frontmost.

## Testing

Unit tests (existing test target):

- SettingsStore: defaults, persistence round-trip, migration of the existing
  `isFormattingEnabled` key.
- HistoryStore retention matrix: off (no save), limit 10, limit lowered
  (immediate prune), unlimited (no prune), clearAll.
- KeyMonitor decision logic: hold-mode press/release/short-tap/Space
  transitions; toggle-mode press-starts / press-stops; mode-change while
  recording stops cleanly.

Manual verification: command-line build; launch; both modes across each
hotkey choice; Settings opens from the popover while another app is
frontmost; launch-at-login toggle reflects real SMAppService state.
