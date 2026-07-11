# Context-Aware Coding Corrections — Design

**Date:** 2026-07-11
**App:** Dict (macOS 26.4 menu-bar dictation app, fully on-device)

## Goal

Make Dict interpret dictation differently depending on the app you are dictating
into. Specifically: when the frontmost app is a coding or terminal app, the
on-device formatter should correct domain-specific homophones and jargon —
"merge into Maine" → "merge into main", "get commit" → "git commit",
"jason" → "JSON" — instead of transcribing them literally. In every other app,
behavior is unchanged.

## Decisions (settled during brainstorming)

- **Mechanism:** the on-device LLM infers corrections from the app context. No
  hand-maintained substitution dictionary of terms.
- **Scope:** coding / terminal apps only, for now. One context category.
- **Control:** folded into the existing **Format Transcripts** toggle — no new
  setting. Corrections happen when formatting is on *and* you are in a coding
  app.
- **Detection:** a curated allowlist of coding/terminal app bundle IDs, grown
  over time.
- **Integration:** Approach A — one formatter, two prompt variants (verbatim vs.
  coding), selected by an injected context value. One model pass, same cost and
  safety machinery as today.

## The verbatim-guarantee tension

Today's `TranscriptFormatter` promises it **never changes a word** — punctuation
and capitalization only, enforced by a word-count sanity check. Coding
correction deliberately *changes* words ("Maine" → "main"), so it cannot ride on
the verbatim prompt. It is a distinct prompt with a different risk profile,
selected only for coding apps. The verbatim guarantee remains the default for
every non-coding app.

## Architecture

Four small units; one is new. AppKit/bundle-ID knowledge is kept out of the
formatter so the formatter stays pure and testable.

### `CodingAppCatalog` (new)

A curated `Set<String>` of known dev-tool bundle IDs plus a pure classifier:

```swift
enum CodingAppCatalog {
    static let bundleIDs: Set<String> = [ /* see list below */ ]

    /// True when the given bundle ID belongs to a known coding/terminal app.
    /// A nil or unknown ID is never treated as coding.
    static func isCodingApp(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return bundleIDs.contains(bundleID)
    }
}
```

Initial allowlist (extensible; grown over time):

- **Terminals:** `com.apple.Terminal`, `com.googlecode.iterm2`,
  `com.mitchellh.ghostty`, `dev.warp.Warp-Stable`, `org.alacritty`,
  `net.kovidgoyal.kitty`, `com.github.wez.wezterm`, `io.alacritty`,
  `com.raphaelamorim.rio`
- **Editors / IDEs:** `com.microsoft.VSCode`, `com.microsoft.VSCodeInsiders`,
  `com.vscodium`, `com.todesktop.230313mzl4w4u92` (Cursor), `dev.zed.Zed`,
  `com.apple.dt.Xcode`, `com.sublimetext.4`, `com.panic.Nova`,
  `com.jetbrains.intellij`, `com.jetbrains.intellij.ce`,
  `com.jetbrains.pycharm`, `com.jetbrains.pycharm.ce`,
  `com.jetbrains.WebStorm`, `com.jetbrains.goland`, `com.jetbrains.CLion`,
  `com.jetbrains.rubymine`, `com.jetbrains.PhpStorm`,
  `com.jetbrains.datagrip`, `com.jetbrains.rider`, `com.jetbrains.AppCode`

### `FormattingContext` (new)

The single value that flows into the formatter, keeping it ignorant of AppKit:

```swift
enum FormattingContext {
    case general   // verbatim: punctuation + capitalization only
    case coding    // verbatim behavior + coding homophone/jargon correction
}
```

### `TranscriptFormatter` (modified)

- `format(_ raw: String, context: FormattingContext = .general) async -> String`
  gains the context argument (defaulted, so existing call sites and tests keep
  compiling).
- Add a `static let codingInstructions` prompt: everything the verbatim
  `instructions` prompt does (add punctuation and capitalization, preserve every
  spoken word and its order, never answer questions, insert paragraph breaks
  only on clear topic shifts) **plus** an explicit instruction to fix obvious
  coding/terminal homophones and jargon, driven by a worked example (the model
  follows examples far more reliably than rules).
- `format` selects instructions by context:
  `let instructions = context == .coding ? Self.codingInstructions : Self.instructions`
  and passes them into the existing per-chunk session creation.
- **All other machinery is reused unchanged:** chunking (`chunked`), the 15s
  per-chunk timeout, the word-count sanity check (`isAcceptable`), and every
  failure path returning the raw transcript.

Worked example for the coding prompt (illustrative):

```
Example input:
lets merge into maine after we get commit the jason config and rerun the a p i tests

Example output:
Let's merge into main after we git commit the JSON config and rerun the API tests.
```

### `PipelineCoordinator` (modified)

In `stopRecordingAndProcess`, between getting `rawText` and formatting:

```swift
let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
let context: FormattingContext = CodingAppCatalog.isCodingApp(bundleID) ? .coding : .general
let text = isFormattingEnabled ? await formatter.format(rawText, context: context) : rawText
```

Requires `import AppKit` in `PipelineCoordinator.swift` (currently `Foundation`
only).

## Data flow

```
activeEngine.stop() → rawText
  → read NSWorkspace.shared.frontmostApplication?.bundleIdentifier
  → CodingAppCatalog.isCodingApp(bundleID) ? .coding : .general
  → formatter.format(rawText, context:)      (only if isFormattingEnabled)
  → historyStore.save → textInsertionService.insertText
```

The frontmost app is read **once, at stop**, right before formatting — the same
instant we are about to decide where the text lands. Dict is a menu-bar
`LSUIElement` app that never takes focus, so the frontmost app is the target app
being dictated into (the same reason paste works today). Reading at stop (rather
than start) matches the paste target if the user switched apps mid-dictation.

## Error handling — every path degrades safely

- **Nil or unknown bundle ID** → `.general` → today's verbatim formatting.
  Unknown apps are never treated as coding.
- **Formatting disabled** → context is computed but unused; raw text passes
  through exactly as now.
- **Coding-prompt model failure / timeout / sanity-check rejection** → falls
  back to the **raw transcript**, identical to the existing formatter safety
  net.
- **Word-count sanity check** stays as-is. Coding corrections are overwhelmingly
  1:1 word swaps ("Maine" → "main"), so they pass; a run where the model
  over-rewrites is correctly rejected and the raw transcript is used instead.

Net risk profile: the worst case in a coding app is the same output you would
get today. The feature can only improve or no-op — never corrupt.

## Testing

Mirrors how the existing formatter is tested: pure helpers unit-tested; LLM
output quality validated by hand.

- **`CodingAppCatalogTests` (new, Swift Testing):** representative dev-tool IDs
  (`com.apple.Terminal`, `com.microsoft.VSCode`, `dev.zed.Zed`,
  `com.apple.dt.Xcode`) → `true`; non-coding IDs (`com.apple.Safari`,
  `com.apple.mail`, `com.apple.Notes`), an unknown ID, and `nil` → `false`.
  Locks the allowlist against accidental edits.
- **`TranscriptFormatter`:** existing `chunked` / `isAcceptable` tests unchanged.
  Add a test that empty input returns the input unchanged regardless of context
  (both `.general` and `.coding`) — the model-independent guard path. Correction
  quality ("Maine" → "main") is a manual smoke test on-device; the on-device
  model is not deterministic enough for a unit assertion, matching how the
  current formatter's quality is validated.
- **`NSWorkspace` read** stays a one-line impure edge in `PipelineCoordinator`,
  not unit-tested (consistent with other AppKit edges in the app).

## UI / discoverability

No new setting (folded into Format Transcripts). One clarifying line added to the
existing Format Transcripts caption in `SettingsView`, so the behavior is not
invisible:

> "In coding and terminal apps, it also fixes technical terms like 'main' and
> 'git'."

That is the entire UI change.

## Files

- **Create:** `Dict-app/CodingAppCatalog.swift` (`CodingAppCatalog` +
  `FormattingContext`)
- **Modify:** `Dict-app/TranscriptFormatter.swift` (context arg + coding prompt)
- **Modify:** `Dict-app/PipelineCoordinator.swift` (read frontmost app, pass
  context; `import AppKit`)
- **Modify:** `Dict-app/SettingsView.swift` (one caption line)
- **Create:** `Dict-appTests/CodingAppCatalogTests.swift`
- **Modify:** `Dict-appTests/` formatter tests (empty-input-with-context case)

## Global constraints

- Deployment target macOS 26.4; Swift/SwiftUI/AppKit; fully on-device (no
  servers, no network beyond each engine's own asset download).
- New `.swift` files under `Dict-app/` and `Dict-appTests/` are auto-included via
  `PBXFileSystemSynchronizedRootGroup` — do **not** edit `project.pbxproj` to add
  files.
- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`) — not XCTest.
- Version-bump commits (if any) use `<marketingVersion> build <buildNumber>`.
