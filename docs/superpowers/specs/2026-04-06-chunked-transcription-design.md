# Chunked Transcription Design

## Problem

Long dictation sessions take too long to transcribe because the entire audio is processed as one file after the user stops recording. Users wait proportionally to how long they spoke.

## Solution

Split audio into segments on natural silence boundaries during recording. Transcribe completed segments in the background while the user continues speaking. When the session ends, only the final segment needs transcription — earlier segments are already done.

## Architecture

Three new/modified components alongside the unchanged `AudioRecorder`:

### SegmentedRecordingCoordinator (new)

Monitors audio levels during a recording session and manages segment splitting.

**State machine:**
- **Recording** — AudioRecorder is writing to a file. A silence timer resets whenever audio level exceeds the speech threshold.
- **Waiting** — Silence lasted ~1.5s. The segment was finalized and sent to TranscriptionQueue. AudioRecorder is in monitor-only mode (engine running, RMS computed, no file). Waiting for speech to resume.
- **Stopped** — User ended the session. Any in-progress segment is finalized.

**Transitions:**
- Recording → Waiting: Audio level below silence threshold for ~1.5s continuously
- Waiting → Recording: Audio level exceeds speech threshold → start new file
- Recording → Stopped: User stops → finalize current segment
- Waiting → Stopped: User stops → nothing to finalize

**Key parameters:**
- Silence threshold: RMS level below which audio is considered silence (~0.01–0.02 raw RMS, tunable)
- Silence duration: 1.5s of continuous silence triggers a split
- Speech threshold: RMS level above silence threshold to resume recording

### TranscriptionQueue (new)

Receives segment audio file URLs, transcribes them sequentially via WhisperTranscriptionService, accumulates ordered results.

- Segments submitted with an index for ordering
- Processes sequentially (not concurrently) — avoids Neural Engine contention
- Empty transcription results are silently skipped
- `waitForCompletion() -> String` blocks until all segments done, returns text joined with spaces

### AudioRecorder (modified)

Add monitor-only mode:
- `startMonitoring()` — starts the AVAudioEngine with an input tap that computes RMS levels but does not write to a file
- `stopMonitoring()` — stops the engine and tap
- Existing `startRecording()` / `stopRecording()` unchanged

### PipelineCoordinator (modified)

Replace single record→transcribe flow with:
- `startSession()` — creates SegmentedRecordingCoordinator + TranscriptionQueue
- `stopSession() async -> String?` — finalizes recording, waits for queue, returns assembled text
- Still handles history save and text insertion

## Data Flow

1. User triggers recording → PipelineCoordinator starts session
2. SegmentedRecordingCoordinator starts AudioRecorder (segment 0)
3. User speaks, pauses for 1.5s → segment 0 finalized, submitted to queue
4. AudioRecorder enters monitor-only mode, queue transcribes segment 0
5. User resumes speaking → new recording started (segment 1)
6. User stops session → segment 1 finalized, submitted to queue
7. Queue finishes remaining segments → returns "segment 0 text segment 1 text"
8. PipelineCoordinator saves to history, pastes text

## Error Handling

- Transcription fails for a segment: log, skip, assemble remaining text
- AudioRecorder fails to start new recording: log, stay in Waiting, retry on next speech detection
- No segments produced: return nil (same as current empty-transcription behavior)
- Temp file cleanup: WhisperTranscriptionService deletes files after transcription; coordinator cleans up files for skipped/failed segments

## Edge Cases

- Extended silence (30s+): One split occurs, then coordinator sits in Waiting state. No files created until speech resumes.
- Very short utterance between pauses: Gets its own segment. If transcription returns empty, it's skipped.
- User stops during silence (Waiting state): No final segment to process, queue assembles whatever was already transcribed.
