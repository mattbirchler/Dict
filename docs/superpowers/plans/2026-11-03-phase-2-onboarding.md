# Phase 2: Onboarding and First Impression

**Goal:** A stranger opens Dict for the first time and, within two minutes, has dictated into a text field and watched the words land. Then the extras that make hold-to-talk feel confident: any key as the shortcut, and sounds.

**Spec:** `docs/audit-2026-11-02.md` section 4 (flow) and section 3 items 5 and 6 (shortcut recorder, sounds). Matt's picks: O1 multi-step onboarding, O2 "Try it", O3 Apple first with auto-switch to Parakeet, O4 shortcut recorder, O5 sounds. O6 (menu bar state) shipped with the Matrix restyle.

**Look:** The Matrix language from `docs/../memory`: dark panel, `HUDColorScheme` accents, `HUDFont` uppercase labels, `DotMatrix` where a live element earns it. Native controls for toggles, buttons and text fields.

## Global constraints

- No em dashes in user-facing text.
- One commit per task. Build with `make build`, test with `make test`.
- Review each screen with `Dict --preview-onboarding <step> --snapshot out.png` (added in Task 1) before calling it done.
- Onboarding must work for a user who already granted everything (re-running from the menu): every step shows its granted state and Continue is enabled.

## Tasks

### Task 1: Multi-step onboarding (O1)

- `OnboardingFlow.swift`: `enum OnboardingStep { welcome, listen, accessibility, chooseKey, tryIt, accuracy, done }`, `OnboardingFlow.steps(engine:)`, `canContinue(step:, mic:, speech:, accessibility:, engineReady:)`. Pure, tested in `OnboardingFlowTests`.
- `OnboardingWindow.swift` rewritten: one view per step, LED progress dots, Back and Continue, forced dark appearance. Accessibility step polls every second and auto-advances; the app installs the key monitor as soon as the grant lands (`AppState.onAccessibilityGranted`).
- Choose your key: four key caps, pressing the physical key picks it (NSEvent local monitor), hold vs toggle below, the Space trick explained.
- Preview mode `--preview-onboarding <step>`.

### Task 2: "Try it" (O2)

- A text field in the Try it step with the instruction "Hold ⌘ and say anything". The real pipeline inserts into it. A lit checkmark and "That's it" once text arrives. Continue enabled once the engine is ready, regardless (people can skip the test).

### Task 3: Apple first, Parakeet in the background (O3)

- `AppState.downloadParakeet()`: prepares the Parakeet engine without switching to it, mirrors progress in `parakeetDownloadProgress`, switches `settings.transcriptionEngine` to `.parakeet` when done. Works from the Accuracy step and from Settings.
- Dictation keeps working on Apple during the download. Tested: a completed background prepare flips the setting; a failed one leaves Apple selected and reports.

### Task 4: Shortcut recorder (O4)

- `HotkeyChoice` grows a `.custom(keycode:modifiers:)` case stored as JSON; `KeyMonitor` matches it. A recorder control (click, press keys, shows the combo) in Settings and in the Choose your key step. Modifier-only choices stay as the quick picks.

### Task 5: Sounds (O5)

- Three short bundled sounds (start, stop, inserted), played through `NSSound`, a Settings toggle `playsSounds` (on by default, quiet), never during `--preview-*`.
