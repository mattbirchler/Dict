# Privacy

Dict is built so that what you say never leaves your Mac.

## What stays on your Mac

- **Audio.** Captured from the microphone only while you hold the hotkey (or
  while hands-free mode is on), kept in memory for transcription, and
  discarded when the text is inserted. Dict never writes audio to disk.
- **Transcripts.** Produced by a speech model running on your Mac (Apple's
  built-in speech recognition, or the Parakeet model). Formatting uses the
  on-device Apple Intelligence model when it's available.
- **History.** Recent transcriptions are stored in a local database
  (`~/Library/Application Support/Dict/History.store`) so you can copy
  them again. You choose how many to keep (or none) in History.
- **Settings and word replacements.** Stored in Dict's preferences file.
- **The field you dictate into.** When formatting runs, Dict reads the text
  already in the focused field (through the Accessibility permission) and
  hands the on-device formatter the names and terms it finds there, so they
  are spelled the way your document spells them. The text is used for that
  one dictation and never stored or sent anywhere. Turn this off in
  Settings > General if you prefer.

## The only network connections

1. **Model download.** The first time you choose the Parakeet engine, Dict
   downloads the model (about 500 MB) from `huggingface.co`, from the
   `FluidInference/parakeet-tdt-0.6b-v3-coreml` repository. The request
   carries nothing about you. The model is cached in
   `~/Library/Application Support/FluidAudio/Models`.
2. **Update check.** Dict uses Sparkle to check
   `https://raw.githubusercontent.com/mattbirchler/Dict-app/main/appcast.xml`
   once a day, and when you choose Check for Updates. That request includes
   Dict's version and your macOS version, as every update check does, and
   nothing else. Sparkle's optional system-profile reporting is off.

There are no accounts, no analytics, no crash reporting, and no other
connections. The Apple speech engine runs on-device; on macOS 26 and later
it does not send audio to Apple.

## Removing everything

Quit Dict, then delete:

- `/Applications/Dict.app`
- `~/Library/Application Support/FluidAudio` (the Parakeet model)
- `~/Library/Preferences/birchtree.Dict-app.plist` (settings)
- `~/Library/Application Support/Dict` (the history database)

Dict's Microphone and Accessibility permissions can be removed in System
Settings > Privacy & Security.
