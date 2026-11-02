# Dict

Dict is a free dictation app for the Mac that runs entirely on your device.
Hold a key, talk, let go, and the words land wherever your cursor is. Nothing
you say leaves your Mac.

## Requirements

- macOS 26 or later
- Apple silicon

## Install

1. Download the latest `Dict-<version>-<build>.zip` from
   [Releases](https://github.com/mattbirchler/Dict-app/releases).
2. Unzip it and open Dict. It offers to move itself to your Applications
   folder; say yes, so macOS can remember its permissions and updates can
   install.
3. Grant the permissions it asks for: Microphone, Accessibility (how Dict
   sees the hotkey and pastes text into other apps), and Speech Recognition
   when the Apple engine is selected.

Dict lives in the menu bar. Updates arrive through the app itself (Check for
Updates… in the menu, or automatically once a day).

## How to use

- **Hold the hotkey** (Right Command by default) and speak. Release it and
  the text is inserted into the frontmost app.
- **Hands-free:** tap Space while holding the hotkey. Dict keeps listening
  and shows the words as they form; press the hotkey again to finish.
- **Escape** cancels a recording, or a transcription that's still running.
- Settings has a toggle mode (press to start, press to stop), hotkey and
  microphone pickers, and word replacements for names it keeps mishearing.

## Engines

Dict ships with two on-device speech engines:

- **Apple** uses the speech recognition built into macOS. No download, ready
  immediately.
- **Parakeet** (NVIDIA Parakeet TDT, via FluidAudio) is more accurate and
  punctuates on its own. It's a one-time download of about 500 MB.

Formatting (punctuation, capitalization, and coding-term fixes in editors
and terminals) uses the on-device Apple Intelligence model when it's
available, and never changes the words you said.

## Privacy

Audio, transcripts, history, and settings stay on your Mac. Dict makes two
kinds of network request and nothing else: downloading the Parakeet model
when you choose that engine, and checking for updates. There are no
accounts, no analytics, and no crash reporting. Details in
[PRIVACY.md](PRIVACY.md).

## Building

Open `Dict-app.xcodeproj` in Xcode 27 or later, or from the command line:

```bash
make build        # Debug build
make test         # unit tests (add E2E=1 to include the Parakeet model test)
make install      # Release build into /Applications
```

## Releasing

See [RELEASING.md](RELEASING.md). `make publish NOTES=notes.md` notarizes a
build, signs it for Sparkle, and publishes a GitHub release with the feed.

## License

Dict is released under the [MIT License](LICENSE). It uses
[FluidAudio](https://github.com/FluidInference/FluidAudio) (Apache 2.0),
[Sparkle](https://sparkle-project.org) (MIT), and NVIDIA's Parakeet TDT
model (CC BY 4.0).
