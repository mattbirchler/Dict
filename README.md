<p align="center">
  <img src="docs/readme/icon.png" width="128" alt="Dict app icon: a grid of glowing orange and pink dots on a dark tile">
</p>

<h1 align="center">Dict</h1>

<p align="center">
  Free, private dictation for the Mac. Hold a key, talk, let go.<br>
  Everything runs on your Mac. Nothing you say leaves it.
</p>

<p align="center">
  <a href="https://github.com/mattbirchler/Dict-app/releases/latest"><b>Download for macOS</b></a>
  &nbsp;&middot;&nbsp;
  <a href="https://github.com/mattbirchler/Dict-app/releases">Release notes</a>
  &nbsp;&middot;&nbsp;
  <a href="PRIVACY.md">Privacy</a>
</p>

<p align="center">
  <img src="docs/readme/hero.png" width="720" alt="The Dict panel while recording, and the larger hands-free panel showing words as they arrive">
</p>

## What it is

Dict is a dictation app that lives in your menu bar. Hold the dictation key (Right Command, unless you pick another), say what you want to type, and let go. A moment later the text is sitting in whatever app you were in: a message, a document, a code editor, a search box.

The speech recognition runs on your Mac, using either Apple's built-in engine or NVIDIA's Parakeet model. There is no account, no server, no subscription and no usage limit. Dict is free and the source is right here.

## Why you might want it

- **Private by construction.** Audio, transcripts and history never leave your Mac. The only network requests Dict makes are checking for updates and, if you ask for it, downloading the Parakeet model. Details in [PRIVACY.md](PRIVACY.md).
- **Accurate.** Apple's engine is ready the moment you install. Parakeet is a one-time 500 MB download that is noticeably better on names, technical terms and long sentences, and Dict switches over by itself when the download finishes.
- **Your key, your way.** Use Right Command, Right Option, Right Control or Fn, or record any combination you like. Choose press-and-hold or press-to-toggle.
- **Hands-free when you need it.** Tap Space while holding the key and Dict keeps listening until you press Command to finish. The panel grows to show the words as they arrive.
- **Three dictation styles.** Verbatim keeps every word. Clean drops the ums, uhs and repeated words, and keeps only your corrected version when you change your mind mid-sentence. Polished adds small grammar fixes. Clean and Polished use Apple Intelligence on your Mac, so nothing leaves it.
- **Knows what you're typing into.** Dict reads the field you are dictating into and spells names, acronyms and identifiers the way they already appear there. In editors and terminals it formats code terms properly. Both can be turned off.
- **Word replacements.** Teach Dict the words it keeps getting wrong.
- **History and stats.** Every dictation is kept on your Mac, with a limit you choose, and the top of the list shows words dictated, time saved and your day streak.
- **Looks the part.** A small panel with a live spectrum in five color schemes: Ember, Phosphor, Glacier, Ultraviolet and Graphite.

<p align="center">
  <img src="docs/readme/schemes.png" width="404" alt="The recording panel in each of the five color schemes">
</p>

## Install

1. [Download the latest disk image](https://github.com/mattbirchler/Dict-app/releases/latest) (`Dict-<version>-<build>.dmg`).
2. Open it and drag Dict to the Applications folder, then open Dict from there.
3. Follow the short setup. Dict asks for Microphone access so it can hear you and Accessibility access so it can type for you, and explains each one as it goes. You get to try dictating before setup is over.

Dict needs **macOS 26 or later** on a Mac with **Apple silicon**. Updates arrive through the app itself: Check for Updates in the menu, or automatically once a day.

<p align="center">
  <img src="docs/readme/onboarding.png" width="520" alt="The setup step where you try dictating into a text box">
</p>

## Using Dict

| Do this | And Dict |
| --- | --- |
| Hold the key and speak, then let go | types what you said where your cursor is |
| Tap Space while holding the key | goes hands-free and keeps listening; press Command to finish |
| Press Escape | cancels the recording, or a transcription still in progress |
| Open the menu bar icon | shows a dictation style switcher, Copy Last Dictation, History and Settings |

The menu bar icon follows the microphone while you talk, so you can see Dict is listening even when the panel is off to the side.

<p align="center">
  <img src="docs/readme/states.png" width="404" alt="The panel while recording, while processing, and after the text is inserted">
</p>

## Settings and history

<p align="center">
  <img src="docs/readme/settings.png" width="720" alt="The General settings: launch at login, dictation hotkey, activation mode, microphone and live words">
</p>

<p align="center">
  <img src="docs/readme/history.png" width="720" alt="The History window with lifetime stats at the top and recent dictations below">
</p>

## The two engines

| | Apple | Parakeet |
| --- | --- | --- |
| Where it runs | On your Mac | On your Mac |
| Download | None, ready immediately | About 500 MB, once |
| Strengths | Instant start, shows words as you speak | Better accuracy on names, jargon and long dictations; punctuates on its own |
| Languages | English (US) | 25 European languages |

Switch between them in Settings. Punctuation, capitalization and the Clean and Polished styles use the on-device Apple Intelligence model when it is available, and never change the words you said. Without Apple Intelligence, Clean and Polished fall back to a narrow rule-based pass that only removes filler sounds.

## Privacy, in one paragraph

Audio, transcripts, history, settings and the text Dict reads from your screen stay on your Mac. Dict makes two kinds of network request and nothing else: downloading the Parakeet model when you choose that engine, and checking GitHub for updates. There are no accounts, no analytics and no crash reporting. [PRIVACY.md](PRIVACY.md) has the full statement.

## Found a problem?

[Open an issue](https://github.com/mattbirchler/Dict-app/issues). The About window has a Copy Diagnostic Log button; the log contains timings and error messages, never your audio or text.

## For developers

Dict is Swift 6 and SwiftUI, built with Xcode 27 or later. The speech engines are Apple's `SpeechAnalyzer` and [FluidAudio](https://github.com/FluidInference/FluidAudio) running Parakeet TDT through Core ML. Formatting uses Apple's Foundation Models framework.

```bash
make build        # Debug build
make test         # unit tests (add E2E=1 to include the Parakeet model test)
make install      # Release build into /Applications
```

The app has preview modes for looking at the panel and windows without dictating, for example `Dict --preview-hud recording --snapshot out.png`. See `HUDPreview.swift`. Releases are built with `make publish`; the steps are in [RELEASING.md](RELEASING.md).

## License and thanks

Dict is released under the [MIT License](LICENSE). It is built on [FluidAudio](https://github.com/FluidInference/FluidAudio) (Apache 2.0), NVIDIA's Parakeet TDT model (CC BY 4.0), [Sparkle](https://sparkle-project.org) (MIT) for updates, and the [Chakra Petch](https://fonts.google.com/specimen/Chakra+Petch) typeface (OFL) for the panel's labels.
