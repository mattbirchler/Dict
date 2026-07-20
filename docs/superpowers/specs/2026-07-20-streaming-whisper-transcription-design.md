# Streaming Whisper Transcription Design

## Problem

Dictation text appears too long after the user releases the hotkey. Today the
entire recording is decoded in one shot inside `StreamingTranscriptionService.stop()`,
so the wait after key-up grows with how long the user spoke.

Goal: move decode work *earlier*, so that at key-up only a short tail remains.

## Context: two prior attempts

This is the third pass at this idea. Both earlier attempts underdelivered, and
this design is shaped by why.

**`2026-04-06-chunked-transcription-design.md`** targeted the old file-based
`AudioRecorder`, which no longer exists. Its `SegmentedRecordingCoordinator`
dropped into a monitor-only "Waiting" state between segments, which
**discarded audio during silence gaps**. That clips word onsets when speech
resumes, and it means the full recording is no longer recoverable.

**Commit `5f49d83` ("transcribe speech segments while recording", reverted in
`5614182`)** added a `SpeechSegmentAccumulator` to the WhisperKit path. Four
problems:

1. **Wrong engine.** It only touched `StreamingTranscriptionService`, while the
   app's default and the user's setting at the time were `.apple`. It produced
   no speedup at all in the configuration actually being used.
2. **Chunks far too small.** `minimumSegmentDuration: 1.5s` gives Whisper almost
   no context, which is where boundary errors and hallucinated fragments come
   from.
3. **Constant pipeline contention.** Chunk decodes and the final decode share
   one WhisperKit pipeline, serialized. At 1.5s chunks the decoder is nearly
   always busy, so the tail decode routinely queued behind an in-flight chunk.
   This could make key-up latency *worse*.
4. **Bypassed the adaptive gate.** Segmentation used the fixed
   `VoiceGate.absoluteFloor` rather than the noise-floor adaptation that
   `gateAndTrim` performs, so it disagreed with the production trim. Per-chunk
   VAD also changes what `TranscriptFilter` can catch, since that filter is
   designed around whole-recording voice activity.

## Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Engine | WhisperKit only | User has switched to `.whisper` for accuracy. Apple's SpeechAnalyzer is natively streaming and would be a separate, much smaller piece of work. |
| Quality bar | Latency first, protect quality | Generous chunk sizes plus decoder context, not aggressive splitting. |
| Formatting pass | Out of scope | The Foundation Models formatting call stays exactly as it is. |
| Live HUD preview | Out of scope | The goal is text landing sooner after release. Text inserted into another app cannot be revised afterward. |
| Streaming toggle | No user setting | The fallback path covers safety. A toggle adds a settings surface and a support question for something that should simply be correct. |

## Non-goals

- Changing `PipelineCoordinator`, `TranscriptFormatter`, or the insertion path.
- Any change to the Apple engine.
- Showing partial text while the user is still speaking.

## Architecture

Public surface is unchanged: `start()`, `cancel()`, and `stop() async -> String`
keep their signatures, so `PipelineCoordinator` needs no edits. All new
behavior lives inside `StreamingTranscriptionService` and three new units.

### SpeechSegmenter (new, pure)

A struct with no I/O, so it is fully unit-testable. Given newly arrived samples
and the session's noise floor, it decides where a chunk ends.

Boundary policy:

- **Minimum chunk duration: 4s.** Enough audio for Whisper to decode well.
- **Split only on trailing silence >= 0.6s.** Guarantees we never cut mid-word.
- **Minimum voiced audio: 1.0s.** A chunk of nothing but breath is not worth decoding.
- **Hard cap: 20s.** Forces a split so long monologues still stream. Whisper's
  window is 30s, so this stays comfortably inside it.

The noise floor is estimated once per session and shared by every chunk. If each
chunk adapted independently, a quiet chunk and a loud chunk would disagree about
what silence is. This is the specific flaw in `5f49d83`'s use of a fixed floor.

### ChunkDecodeQueue (new)

Owns serialized access to the single WhisperKit pipeline. At most one decode in
flight. Accepts a high-priority tail submission at key-up.

A Core ML decode in flight cannot be cheaply interrupted, so the tail may wait
behind at most **one** chunk decode. The chunk size cap is what bounds that
worst case. This is the direct fix for problem 3 above.

Each chunk decode passes `DecodingOptions.promptTokens`, built by tokenizing the
**last 200 characters** of the accumulated transcript so far via
`WhisperKit.tokenizer`, truncated to the final 100 tokens if the tokenizer yields
more. This is the context carry-over that protects boundary quality. (Both
`promptTokens` and `tokenizer` are verified public API in the pinned WhisperKit.)

### TranscriptAssembler (new, pure)

Joins chunk texts in order with a single space and strips prompt-induced
repetition at boundaries. Whisper will sometimes re-emit the tail of its prompt,
so the assembler compares the **last 15 words** of chunk *n-1* against the
**first 15 words** of chunk *n*, finds the longest word-sequence match of at
least 3 words, and drops it from the head of chunk *n*. Comparison is
case-insensitive and ignores punctuation; the retained text keeps chunk *n-1*'s
original casing and punctuation.

### StreamingTranscriptionService (modified)

Orchestration and lifecycle only.

Segmentation is driven from the **existing 0.05s waveform timer**, tracking a
cursor into `audioProcessor.audioSamples`. No `AsyncStream`, no audio-thread
callback, no extra consumer task. This is a deliberate simplification over
`5f49d83`, which introduced all three.

## Data flow

```
key-down → startRecordingLive (audioSamples accumulates continuously)
            │
   0.05s timer (already exists for the waveform)
            │ new samples since cursor
            ▼
      SpeechSegmenter ──chunk complete──► ChunkDecodeQueue
            │                                  │ decode with promptTokens
            │                                  │ from prior chunk's tail
            │                                  ▼
            │                            completedChunks[i]
            ▼
key-up → segmenter.finish() → tail ──enqueued high priority──► decode
                                                                  │
                                            TranscriptAssembler ◄──┘
                                                                  │
                                                        return final text
```

**Audio is never discarded.** `audioProcessor.audioSamples` retains the whole
recording regardless of chunking. This is what makes the fallback below possible,
and it is the key correction to the April design.

## Where the win comes from, and its limit

Total decode work is roughly proportional to audio length either way. Streaming
wins by moving that work earlier, leaving only the final pause-to-release tail at
key-up. This pays off only because `distil-large-v3` decodes faster than realtime
on Apple Silicon.

**Honest limitation:** a single unbroken 30-second sentence with no pauses
produces no chunk boundaries, and latency equals today's. Approach A helps
speech with natural pauses, which is the common case for dictation, but it is not
a universal win.

## Fallback and error handling

Because the full buffer is retained, `stop()` can always retreat to the current
one-shot `gateAndTrim` + full decode. Streaming is a pure optimization.

Fallback triggers:

- Any chunk decode throws.
- No chunk boundaries were ever found. The tail is then the whole recording, so
  this is naturally identical to today's behavior.
- Assembled text is empty while `gateAndTrim(samples:)` on the full buffer
  returns non-nil, i.e. the recording did contain detectable voice.

Per-component handling:

- **Chunk decode failure:** mark the session degraded, discard partial results,
  take the fallback path. Never surface a half-transcript.
- **Cancel mid-recording:** bump the existing `session` counter, cancel the
  queue, discard chunks. That counter already guards the "cancelled while
  suspended in `ensureLoaded`" race and is retained as-is.
- **Repeat sessions:** all chunk state (cursor, completed chunks, segmenter)
  resets in `start()`, not only in `stop()`. State reset only on the success path
  leaks whenever the failure path runs. This is the lesson from the
  second-dictation crash fixed in `0b16828`, where a per-session object was given
  a lifetime longer than its session.

`TranscriptFilter` receives, for each chunk, a VAD array computed against the
shared session noise floor, so it sees a consistent baseline rather than a
different one per chunk.

## Edge cases

- **All silence:** no chunks, no tail, returns empty, exactly as today.
- **Speech shorter than the 4s minimum:** never chunked, decoded once at key-up.
- **Very long pause mid-dictation:** one split, then the segmenter idles. Audio
  keeps accumulating but produces no voiced chunk.
- **Cancel while a chunk decode is in flight:** the decode result is dropped by
  session-counter mismatch.

## Testing

- **`SpeechSegmenterTests`** (pure, fast): splits only after the minimum
  duration, never splits without trailing silence, honors the hard cap, handles
  all-silence and no-silence inputs.
- **`TranscriptAssemblerTests`** (pure, fast): ordering, spacing, and boundary
  de-duplication when the prompt causes repetition.
- **`StreamingEquivalenceTests`**: synthesize a multi-sentence utterance with
  real pauses via `/usr/bin/say`, run it through both the streaming path and the
  one-shot path, and assert semantic equivalence: key phrases present, no dropped
  trailing words. Follows the existing `EndToEndTranscriptionTests` pattern.
- **`StreamingRepeatSessionTests`**: three back-to-back streaming sessions,
  guarding the state-leak class of bug.

**Ship gate:** `StreamingEquivalenceTests` is the acceptance criterion. If
streamed output cannot match one-shot quality on the fixture, we ship the
fallback and not the feature.

## Risks

- Boundary quality may still disappoint even with context carry-over. The
  upgrade path is overlapping sliding windows with stitching, which heals
  boundaries better at the cost of decoding the overlap twice.
- Chunk decodes compete with the tail decode for the Neural Engine. Bounded, not
  eliminated, by the chunk size cap.
- Real-world latency improvement is unmeasured. The plan should begin by
  instrumenting the current one-shot path so the gain is a number, not a claim.
