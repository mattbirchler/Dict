# Hallucination Filtering + On-Device Formatting — Design

**Date:** 2026-07-02
**Status:** Approved

## Problem

Two quality gaps versus apps like Wispr Flow and Aqua Voice:

1. **Silence hallucinations.** Sitting in silence while recording produces
   "Thank you." / "Thanks for watching!" in the transcript. This is a known
   Whisper artifact: silence in its training data often preceded sign-off
   captions, so silent audio decodes to those phrases *with high confidence*.
   Whisper's built-in suppression only drops a segment when `noSpeechProb`
   is high **and** `avgLogprob` is low, so confident hallucinations pass.
   The app currently runs WhisperKit's default thresholds and still
   exhibits the bug.

2. **Formatting.** Output is one unpunctuated-feeling wall of text. Competing
   apps run an LLM post-processing pass over the raw transcript to fix
   punctuation, break paragraphs, and remove filler words.

## Decisions

- Hallucination fix: **layered deterministic filter** (VAD gate + per-segment
  confidence filter + guarded phrase blocklist). No LLM involvement.
- Formatting: **Apple Foundation Models** (on-device LLM, macOS 26+).
  No cloud, no API key. Cleanup level: punctuation, capitalization,
  paragraph breaks, filler-word removal, and stitching obvious
  self-corrections — never rewording or adding content.
- Any formatting failure falls back to inserting the raw (filtered)
  transcript. Dictation must never break because formatting hiccupped.

## Data flow

```
stop pressed
  → samples from AudioProcessor
  → VAD gate (EnergyVAD): no speech at all? → return "", type nothing
  → trim leading/trailing silence (with padding)
  → WhisperKit transcribe (unchanged decoding options)
  → TranscriptFilter: drop hallucinated segments → raw text
  → TranscriptFormatter (Foundation Models): punctuation, paragraphs, fillers
      ↳ on any failure: use raw text unchanged
  → save formatted text to history → insert into frontmost app
```

## Components

### TranscriptFilter (new file, pure logic)

Struct with no audio/UI dependencies. Input: WhisperKit `TranscriptionSegment`s
(`text`, `noSpeechProb`, `avgLogprob`, `start`/`end`) plus the VAD
voice-activity map. Output: joined cleaned text.

Per-segment rules:

- **Confidence drop:** discard when `noSpeechProb > 0.5` (tunable constant).
  OR logic — deliberately stricter than Whisper's built-in AND.
- **Guarded blocklist:** discard when the normalized text (lowercased,
  punctuation stripped) exactly matches a known hallucination phrase
  ("thank you", "thanks for watching", "bye", "you", etc.) **and** the VAD
  saw little actual speech within the segment's time window. A genuine
  "thank you" spoken over real voice activity passes; one decoded from
  silence does not.

Every dropped segment is logged with text + scores for threshold tuning.

### TranscriptFormatter (new file, Foundation Models)

Wraps `LanguageModelSession` with fixed instructions: fix punctuation and
capitalization, insert paragraph breaks at topic shifts, remove filler words
("um", "uh", "you know"), stitch obvious self-corrections
("Tuesday— no, Wednesday" → "Wednesday"). Never add content, reword, or
"improve" phrasing. Output only the corrected text.

Guardrails (all failures return the raw input text):

- **Availability:** check `SystemLanguageModel.default.availability`;
  unavailable (Apple Intelligence off, model not downloaded) → raw text.
- **Sanity check:** output empty, or loses more than ~15% of input words
  beyond expected filler removal → raw text.
- **Timeout / errors:** any throw or slow response (timeout on the order of
  10s) → raw text.
- **Long transcripts:** the on-device model has a ~4k-token context window,
  so transcripts beyond roughly a thousand words are split at sentence
  boundaries and formatted chunk by chunk, then rejoined.

### Changes to existing files

- **StreamingTranscriptionService.stop():** run `EnergyVAD` over the captured
  samples; return `""` early when no active chunks; trim to the active region
  (± padding) before transcribing; apply `TranscriptFilter` to the resulting
  segments instead of blindly joining `results.map(\.text)`.
- **PipelineCoordinator.stopRecordingAndProcess():** call
  `TranscriptFormatter` between `stop()` and history-save, so history stores
  what was actually typed.

No HUD changes: formatting extends the existing post-stop processing moment
by ~0.5–2s. No settings toggle in v1 — the availability fallback covers Macs
without Apple Intelligence.

## Error handling summary

| Failure | Behavior |
|---|---|
| No speech detected in buffer | Type nothing (as if transcript were empty) |
| All segments filtered out | Type nothing |
| Foundation Models unavailable | Insert raw filtered transcript |
| Formatter throws / times out / fails sanity check | Insert raw filtered transcript |

## Testing

- Unit tests for `TranscriptFilter`: fabricated segments covering confident
  hallucination (high noSpeechProb), blocklist phrase over silence (dropped),
  blocklist phrase over real speech (kept), normal speech (kept).
- Unit tests for `TranscriptFormatter` helpers: sentence-boundary chunking,
  word-loss sanity check.
- Add a test target if the project lacks one.
- Manual end-to-end: normal dictation; hold hotkey in silence; genuine
  "thank you" mid-sentence; long multi-topic ramble (paragraph breaks).
