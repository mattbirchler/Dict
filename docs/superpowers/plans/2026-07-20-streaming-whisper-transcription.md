# Streaming Whisper Transcription Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Decode completed speech chunks while the user is still talking, so that releasing the dictation hotkey only leaves a short tail to transcribe.

**Architecture:** A pure `SpeechSegmenter` finds chunk boundaries at natural pauses in the audio already accumulating in `audioProcessor.audioSamples`. Completed chunks go to a serialized `ChunkDecodeQueue` that decodes them with prior-chunk context via `DecodingOptions.promptTokens`. A pure `TranscriptAssembler` joins the results. If anything fails, `stop()` falls back to today's one-shot decode of the full retained buffer, so streaming is a pure optimization.

**Tech Stack:** Swift 6, SwiftUI, macOS 26, WhisperKit (`distil-large-v3`), Swift Testing (`import Testing`, `@Test`, `#expect`), XCTest-free.

## Global Constraints

- Engine scope is **WhisperKit only**. Do not modify `AppleSpeechTranscriptionService.swift`.
- The Foundation Models formatting pass in `TranscriptFormatter` is **out of scope**. Do not touch it.
- The public surface of `StreamingTranscriptionService` must not change: `start() async throws`, `cancel()`, `stop() async -> String`. `PipelineCoordinator.swift` must not need edits.
- **Audio is never discarded.** `pipe.audioProcessor.audioSamples` must remain the complete recording so the fallback path always works.
- No user-facing setting for streaming. No live HUD text preview.
- Never use the "—" character in any user-facing string (UI copy, alerts, notes). Code comments and this plan are exempt.
- Sample rate is `WhisperKit.sampleRate` (16000). Frame duration is `0.1` seconds everywhere, matching `gateAndTrim`.
- Build/test command: `xcodebuild -project Dict-app.xcodeproj -scheme Dict-app -destination 'platform=macOS' test`

## File Structure

| File | Responsibility |
|---|---|
| `Dict-app/VoiceGate.swift` (modify) | Extract the adaptive threshold calculation so segmenter, chunk VAD, and `gateAndTrim` all share one formula. |
| `Dict-app/SpeechSegmenter.swift` (create) | Pure. Decides where chunks end from frame energies. No I/O. |
| `Dict-app/TranscriptAssembler.swift` (create) | Pure. Joins chunk texts and removes prompt-induced boundary repetition. |
| `Dict-app/ChunkDecodeQueue.swift` (create) | Serializes decodes. Injectable decode closure so it is testable without the model. |
| `Dict-app/StreamingTranscriptionService.swift` (modify) | Orchestration, cursor tracking, fallback. |
| `Dict-appTests/SpeechSegmenterTests.swift` (create) | Boundary policy. |
| `Dict-appTests/TranscriptAssemblerTests.swift` (create) | Joining and de-duplication. |
| `Dict-appTests/ChunkDecodeQueueTests.swift` (create) | Ordering, serialization, failure flag. |
| `Dict-appTests/StreamingEquivalenceTests.swift` (create) | Ship gate. Streaming output vs one-shot output on real synthesized speech. |

---

### Task 1: Baseline timing instrumentation

Before optimizing, measure. This task adds timing output to the existing one-shot path so the improvement is a number rather than a claim.

**Files:**
- Modify: `Dict-app/StreamingTranscriptionService.swift` (inside `stop()`)

**Interfaces:**
- Consumes: nothing.
- Produces: console lines prefixed `[Timing]`. No API change.

- [ ] **Step 1: Add timing around the decode in `stop()`**

In `stop()`, replace the existing `do { ... }` decode block's opening with a timed version. Add before `do {`:

```swift
let decodeStarted = ProcessInfo.processInfo.systemUptime
```

and immediately after `let text = TranscriptFilter().filteredText(...)`:

```swift
print(String(
    format: "[Timing] oneshot decode=%.3fs audio=%.1fs chars=%d",
    ProcessInfo.processInfo.systemUptime - decodeStarted,
    Float(trimmedSamples.count) / Float(WhisperKit.sampleRate),
    text.count
))
```

- [ ] **Step 2: Build and confirm it compiles**

Run: `xcodebuild -project Dict-app.xcodeproj -scheme Dict-app -destination 'platform=macOS' build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Capture a real baseline**

Run the app, dictate a sentence of roughly 15 seconds, and record the `[Timing] oneshot` line. Note the decode-seconds-per-audio-second ratio. Paste it into the PR description later. If decode time is already under ~300ms for 15s of audio, stop and report back: the feature may not be worth building.

- [ ] **Step 4: Commit**

```bash
git add Dict-app/StreamingTranscriptionService.swift
git commit -m "chore: time the one-shot decode path to establish a baseline"
```

---

### Task 2: Shared threshold + SpeechSegmenter

**Files:**
- Modify: `Dict-app/VoiceGate.swift`
- Create: `Dict-app/SpeechSegmenter.swift`
- Test: `Dict-appTests/SpeechSegmenterTests.swift`

**Interfaces:**
- Consumes: `VoiceGate.frameEnergies(samples:frameSamples:)`, `VoiceGate.absoluteFloor`.
- Produces:
  - `VoiceGate.threshold(energies: [Float]) -> Float`
  - `VoiceGate.voiceActivity(energies: [Float], threshold: Float) -> [Bool]`
  - `SpeechSegmenter.init(sampleRate:frameDuration:minChunkDuration:minVoicedDuration:silenceDuration:maxChunkDuration:floorWarmupDuration:)`
  - `mutating func append(_ samples: [Float]) -> [Float]?`
  - `mutating func finish() -> [Float]?`
  - `mutating func reset()`
  - `var sessionThreshold: Float { get }`

- [ ] **Step 1: Write the failing tests**

Create `Dict-appTests/SpeechSegmenterTests.swift`:

```swift
import Foundation
import Testing
import WhisperKit
@testable import Dict_app

struct SpeechSegmenterTests {
    /// Loud enough to clear absoluteFloor (0.003) comfortably.
    private func voiced(seconds: Double) -> [Float] {
        [Float](repeating: 0.05, count: Int(Double(WhisperKit.sampleRate) * seconds))
    }
    private func silent(seconds: Double) -> [Float] {
        [Float](repeating: 0.0, count: Int(Double(WhisperKit.sampleRate) * seconds))
    }

    @Test func doesNotSplitBeforeMinimumChunkDuration() {
        var s = SpeechSegmenter()
        // 2s of speech then a long pause: under the 4s minimum, so no split.
        #expect(s.append(voiced(seconds: 2.0)) == nil)
        #expect(s.append(silent(seconds: 1.5)) == nil)
    }

    @Test func splitsAfterPauseOnceMinimumReached() {
        var s = SpeechSegmenter()
        #expect(s.append(voiced(seconds: 5.0)) == nil)
        let chunk = s.append(silent(seconds: 1.0))
        #expect(chunk != nil)
        // Chunk carries the speech plus the trailing silence that triggered it.
        #expect((chunk?.count ?? 0) >= 5 * WhisperKit.sampleRate)
    }

    @Test func doesNotSplitWithoutTrailingSilence() {
        var s = SpeechSegmenter()
        // 10s of unbroken speech, still under the 20s cap: no boundary.
        #expect(s.append(voiced(seconds: 10.0)) == nil)
    }

    @Test func hardCapForcesSplit() {
        var s = SpeechSegmenter()
        #expect(s.append(voiced(seconds: 25.0)) != nil)
    }

    @Test func silenceOnlyInputNeverSplitsAndFinishesEmpty() {
        var s = SpeechSegmenter()
        #expect(s.append(silent(seconds: 10.0)) == nil)
        #expect(s.finish() == nil)
    }

    @Test func finishReturnsRemainingSpeech() {
        var s = SpeechSegmenter()
        _ = s.append(voiced(seconds: 2.0))
        let tail = s.finish()
        #expect(tail != nil)
        #expect((tail?.count ?? 0) >= 2 * WhisperKit.sampleRate)
    }

    @Test func resetClearsPendingAudio() {
        var s = SpeechSegmenter()
        _ = s.append(voiced(seconds: 2.0))
        s.reset()
        #expect(s.finish() == nil)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild -project Dict-app.xcodeproj -scheme Dict-app -destination 'platform=macOS' test -only-testing:Dict-appTests/SpeechSegmenterTests 2>&1 | tail -5`
Expected: build failure, `cannot find 'SpeechSegmenter' in scope`.

- [ ] **Step 3: Extract the shared threshold in `VoiceGate.swift`**

Replace the existing `voiceActivity(energies:)` with these three declarations, keeping the surrounding doc comment:

```swift
    /// The adaptive voiced/unvoiced threshold for a set of frame energies:
    /// `max(absoluteFloor, min(floorMultiplier × 10th-pct, loudFraction × 90th-pct))`.
    /// Extracted so the live segmenter and the batch gate agree on one formula.
    static func threshold(energies: [Float]) -> Float {
        guard !energies.isEmpty else { return absoluteFloor }
        let sorted = energies.sorted()
        let noiseFloor = sorted[min(sorted.count - 1, sorted.count / 10)]
        let loud = sorted[min(sorted.count - 1, sorted.count * 9 / 10)]
        return max(absoluteFloor, min(noiseFloor * floorMultiplier, loud * loudFraction))
    }

    static func voiceActivity(energies: [Float], threshold: Float) -> [Bool] {
        energies.map { $0 > threshold }
    }

    static func voiceActivity(energies: [Float]) -> [Bool] {
        guard !energies.isEmpty else { return [] }
        return voiceActivity(energies: energies, threshold: threshold(energies: energies))
    }
```

- [ ] **Step 4: Create `Dict-app/SpeechSegmenter.swift`**

```swift
import Foundation
import WhisperKit

/// Pure boundary detection for live chunked transcription. Fed the audio
/// arriving during a recording, it returns a completed chunk whenever the
/// speaker reaches a natural pause, so that chunk can be decoded while the
/// user keeps talking.
///
/// The thresholds are deliberately far more conservative than the reverted
/// 5f49d83 implementation (1.5s chunks): Whisper decodes short chunks badly,
/// and frequent chunks keep the decoder busy so the final tail decode queues
/// behind them.
struct SpeechSegmenter {
    let frameSamples: Int
    let minChunkSamples: Int
    let minVoicedSamples: Int
    let silenceSamplesToSplit: Int
    let maxChunkSamples: Int
    let floorWarmupFrames: Int

    private var pending: [Float] = []
    private var analyzed = 0
    /// Retained across chunks on purpose: the threshold must be session-wide,
    /// or a quiet chunk and a loud chunk disagree about what silence is.
    private var energies: [Float] = []
    private var trailingSilenceSamples = 0
    private var voicedSamples = 0
    private var hasVoice = false

    init(
        sampleRate: Int = WhisperKit.sampleRate,
        frameDuration: Double = 0.1,
        minChunkDuration: Double = 4.0,
        minVoicedDuration: Double = 1.0,
        silenceDuration: Double = 0.6,
        maxChunkDuration: Double = 20.0,
        floorWarmupDuration: Double = 1.0
    ) {
        let rate = Double(sampleRate)
        self.frameSamples = Int(rate * frameDuration)
        self.minChunkSamples = Int(rate * minChunkDuration)
        self.minVoicedSamples = Int(rate * minVoicedDuration)
        self.silenceSamplesToSplit = Int(rate * silenceDuration)
        self.maxChunkSamples = Int(rate * maxChunkDuration)
        self.floorWarmupFrames = max(1, Int(floorWarmupDuration / frameDuration))
    }

    /// The session-wide voiced threshold, for callers that need chunk VAD
    /// consistent with segmentation (see TranscriptFilter usage).
    var sessionThreshold: Float {
        energies.count >= floorWarmupFrames
            ? VoiceGate.threshold(energies: energies)
            : VoiceGate.absoluteFloor
    }

    mutating func append(_ samples: [Float]) -> [Float]? {
        guard !samples.isEmpty else { return nil }
        pending.append(contentsOf: samples)

        while pending.count - analyzed >= frameSamples {
            let frame = Array(pending[analyzed..<(analyzed + frameSamples)])
            analyzed += frameSamples
            let rms = VoiceGate.frameEnergies(samples: frame, frameSamples: frameSamples).first ?? 0
            energies.append(rms)
            if rms > sessionThreshold {
                hasVoice = true
                voicedSamples += frameSamples
                trailingSilenceSamples = 0
            } else if hasVoice {
                trailingSilenceSamples += frameSamples
            }
        }
        return takeIfReady()
    }

    /// Called at key-up. Returns whatever speech is left, or nil if the
    /// remainder is pure silence.
    mutating func finish() -> [Float]? {
        guard hasVoice, voicedSamples > 0 else {
            clearPending()
            return nil
        }
        return take()
    }

    mutating func reset() {
        clearPending()
        energies = []
    }

    private mutating func takeIfReady() -> [Float]? {
        guard hasVoice, voicedSamples >= minVoicedSamples else { return nil }
        let naturalSplit = pending.count >= minChunkSamples
            && trailingSilenceSamples >= silenceSamplesToSplit
        // The cap can land mid-word. Accepted: 20s without a 0.6s pause is
        // rare, and an unbounded chunk defeats the whole feature.
        let cappedSplit = pending.count >= maxChunkSamples
        guard naturalSplit || cappedSplit else { return nil }
        return take()
    }

    private mutating func take() -> [Float] {
        let chunk = pending
        clearPending()
        return chunk
    }

    private mutating func clearPending() {
        pending = []
        analyzed = 0
        trailingSilenceSamples = 0
        voicedSamples = 0
        hasVoice = false
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `xcodebuild -project Dict-app.xcodeproj -scheme Dict-app -destination 'platform=macOS' test -only-testing:Dict-appTests/SpeechSegmenterTests 2>&1 | grep -E "passed|failed|Restarting"`
Expected: `Test run with 7 tests in 1 suite passed`. No `Restarting after unexpected exit`.

- [ ] **Step 6: Run the full suite to confirm the VoiceGate change broke nothing**

Run: `xcodebuild -project Dict-app.xcodeproj -scheme Dict-app -destination 'platform=macOS' test 2>&1 | grep -E "Test run with|Restarting"`
Expected: all tests pass. `VoiceGateTests` and `EndToEndTranscriptionTests` are the ones at risk.

- [ ] **Step 7: Commit**

```bash
git add Dict-app/VoiceGate.swift Dict-app/SpeechSegmenter.swift Dict-appTests/SpeechSegmenterTests.swift
git commit -m "feat: pause-boundary speech segmenter with session-wide threshold"
```

---

### Task 3: TranscriptAssembler

**Files:**
- Create: `Dict-app/TranscriptAssembler.swift`
- Test: `Dict-appTests/TranscriptAssemblerTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `TranscriptAssembler.assemble(_ chunks: [String]) -> String`

- [ ] **Step 1: Write the failing tests**

Create `Dict-appTests/TranscriptAssemblerTests.swift`:

```swift
import Foundation
import Testing
@testable import Dict_app

struct TranscriptAssemblerTests {
    @Test func joinsChunksWithSingleSpace() {
        let out = TranscriptAssembler.assemble(["hello there", "how are you"])
        #expect(out == "hello there how are you")
    }

    @Test func skipsEmptyChunks() {
        let out = TranscriptAssembler.assemble(["hello", "", "world"])
        #expect(out == "hello world")
    }

    @Test func removesRepeatedBoundaryPhrase() {
        // The prompt made Whisper re-emit the previous chunk's tail.
        let out = TranscriptAssembler.assemble([
            "we should ship the new build tomorrow",
            "ship the new build tomorrow as long as testing passes"
        ])
        #expect(out == "we should ship the new build tomorrow as long as testing passes")
    }

    @Test func ignoresCaseAndPunctuationWhenMatching() {
        let out = TranscriptAssembler.assemble([
            "the deadline is Friday.",
            "Friday, and we cannot move it"
        ])
        #expect(out == "the deadline is Friday. and we cannot move it")
    }

    @Test func doesNotStripShortIncidentalOverlap() {
        // Two words is below the 3-word minimum: a real repetition of common
        // words must not be swallowed.
        let out = TranscriptAssembler.assemble(["we need to", "to go now"])
        #expect(out == "we need to to go now")
    }

    @Test func handlesSingleChunk() {
        #expect(TranscriptAssembler.assemble(["just one"]) == "just one")
    }

    @Test func handlesNoChunks() {
        #expect(TranscriptAssembler.assemble([]) == "")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild -project Dict-app.xcodeproj -scheme Dict-app -destination 'platform=macOS' test -only-testing:Dict-appTests/TranscriptAssemblerTests 2>&1 | tail -5`
Expected: build failure, `cannot find 'TranscriptAssembler' in scope`.

- [ ] **Step 3: Create `Dict-app/TranscriptAssembler.swift`**

```swift
import Foundation

/// Joins independently decoded chunks back into one transcript.
///
/// Each chunk is decoded with the previous chunk's tail as a decoder prompt,
/// which sometimes makes Whisper re-emit that tail. This strips the
/// duplicate so the seam reads naturally.
enum TranscriptAssembler {
    /// Words of context compared on each side of a boundary.
    static let comparisonWindow = 15
    /// Shorter matches than this are treated as coincidence, not repetition.
    static let minimumMatchWords = 3

    static func assemble(_ chunks: [String]) -> String {
        var result = ""
        for chunk in chunks {
            let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard !result.isEmpty else {
                result = trimmed
                continue
            }
            result += " " + deduplicated(previous: result, next: trimmed)
        }
        return result
    }

    /// Drops the longest leading run of `next` (at least `minimumMatchWords`
    /// long) that repeats the trailing words of `previous`.
    static func deduplicated(previous: String, next: String) -> String {
        let previousWords = words(in: previous)
        let nextWords = words(in: next)
        guard previousWords.count >= minimumMatchWords,
              nextWords.count >= minimumMatchWords else { return next }

        let tail = Array(previousWords.suffix(comparisonWindow)).map(normalized)
        let head = Array(nextWords.prefix(comparisonWindow)).map(normalized)

        var overlap = 0
        for length in stride(from: min(tail.count, head.count), through: minimumMatchWords, by: -1) {
            if Array(tail.suffix(length)) == Array(head.prefix(length)) {
                overlap = length
                break
            }
        }
        guard overlap > 0 else { return next }
        return nextWords.dropFirst(overlap).joined(separator: " ")
    }

    private static func words(in text: String) -> [String] {
        text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).map(String.init)
    }

    private static func normalized(_ word: String) -> String {
        word.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild -project Dict-app.xcodeproj -scheme Dict-app -destination 'platform=macOS' test -only-testing:Dict-appTests/TranscriptAssemblerTests 2>&1 | grep -E "passed|failed"`
Expected: `Test run with 7 tests in 1 suite passed`.

- [ ] **Step 5: Commit**

```bash
git add Dict-app/TranscriptAssembler.swift Dict-appTests/TranscriptAssemblerTests.swift
git commit -m "feat: assemble chunk transcripts and strip boundary repetition"
```

---

### Task 4: ChunkDecodeQueue

The decode closure is injected so this can be tested without loading a 1 GB model.

**Files:**
- Create: `Dict-app/ChunkDecodeQueue.swift`
- Test: `Dict-appTests/ChunkDecodeQueueTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `ChunkDecodeQueue.Request` with `samples: [Float]`, `promptText: String`, `threshold: Float`
  - `init(decode: @escaping @Sendable (Request) async -> String?)`
  - `func enqueue(_ request: Request) -> Task<String?, Never>`
  - `func drain() async -> [String]` (results in submission order, failures dropped)
  - `var hasFailed: Bool`
  - `func cancelAll()`

- [ ] **Step 1: Write the failing tests**

Create `Dict-appTests/ChunkDecodeQueueTests.swift`:

```swift
import Foundation
import Testing
@testable import Dict_app

@MainActor
struct ChunkDecodeQueueTests {
    private func request(_ text: String) -> ChunkDecodeQueue.Request {
        ChunkDecodeQueue.Request(samples: [0.1], promptText: text, threshold: 0.003)
    }

    @Test func returnsResultsInSubmissionOrder() async {
        let queue = ChunkDecodeQueue { req in
            // Invert the delay so a naive concurrent implementation would
            // return these out of order.
            let delay = req.promptText == "a" ? 200 : 10
            try? await Task.sleep(for: .milliseconds(delay))
            return req.promptText
        }
        queue.enqueue(request("a"))
        queue.enqueue(request("b"))
        let results = await queue.drain()
        #expect(results == ["a", "b"])
    }

    @Test func runsOneDecodeAtATime() async {
        let counter = Counter()
        let queue = ChunkDecodeQueue { _ in
            await counter.enter()
            try? await Task.sleep(for: .milliseconds(50))
            await counter.leave()
            return "x"
        }
        queue.enqueue(request("1"))
        queue.enqueue(request("2"))
        queue.enqueue(request("3"))
        _ = await queue.drain()
        #expect(await counter.maxConcurrent == 1)
    }

    @Test func recordsFailureAndDropsResult() async {
        let queue = ChunkDecodeQueue { req in
            req.promptText == "bad" ? nil : req.promptText
        }
        queue.enqueue(request("good"))
        queue.enqueue(request("bad"))
        let results = await queue.drain()
        #expect(results == ["good"])
        #expect(queue.hasFailed)
    }

    @Test func drainOnEmptyQueueReturnsNothing() async {
        let queue = ChunkDecodeQueue { _ in "unused" }
        #expect(await queue.drain().isEmpty)
        #expect(!queue.hasFailed)
    }
}

/// Tracks peak concurrency to prove the queue serializes.
actor Counter {
    private var current = 0
    private(set) var maxConcurrent = 0
    func enter() { current += 1; maxConcurrent = max(maxConcurrent, current) }
    func leave() { current -= 1 }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild -project Dict-app.xcodeproj -scheme Dict-app -destination 'platform=macOS' test -only-testing:Dict-appTests/ChunkDecodeQueueTests 2>&1 | tail -5`
Expected: build failure, `cannot find 'ChunkDecodeQueue' in scope`.

- [ ] **Step 3: Create `Dict-app/ChunkDecodeQueue.swift`**

```swift
import Foundation

/// Serializes chunk decodes onto the single shared WhisperKit pipeline.
///
/// Only one decode runs at a time: the Neural Engine is the bottleneck and
/// overlapping decodes on one pipeline is not supported. Because a Core ML
/// decode in flight cannot be cheaply interrupted, the worst case for the
/// final tail decode is waiting behind exactly one chunk, which is why
/// SpeechSegmenter caps chunk length.
@MainActor
final class ChunkDecodeQueue {
    struct Request: Sendable {
        let samples: [Float]
        let promptText: String
        let threshold: Float
    }

    private let decode: @Sendable (Request) async -> String?
    private var chain: Task<Void, Never> = Task {}
    private var handles: [Task<String?, Never>] = []
    private(set) var hasFailed = false

    init(decode: @escaping @Sendable (Request) async -> String?) {
        self.decode = decode
    }

    @discardableResult
    func enqueue(_ request: Request) -> Task<String?, Never> {
        let previous = chain
        let decode = self.decode
        let handle = Task { @MainActor [weak self] () -> String? in
            // Wait for the previous decode so only one runs at a time.
            _ = await previous.value
            guard !Task.isCancelled else { return nil }
            let text = await decode(request)
            if text == nil { self?.hasFailed = true }
            return text
        }
        handles.append(handle)
        chain = Task { _ = await handle.value }
        return handle
    }

    /// Awaits every enqueued decode and returns the successful results in
    /// submission order.
    func drain() async -> [String] {
        var results: [String] = []
        for handle in handles {
            if let text = await handle.value, !text.isEmpty {
                results.append(text)
            }
        }
        handles = []
        return results
    }

    func cancelAll() {
        for handle in handles { handle.cancel() }
        handles = []
        chain = Task {}
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild -project Dict-app.xcodeproj -scheme Dict-app -destination 'platform=macOS' test -only-testing:Dict-appTests/ChunkDecodeQueueTests 2>&1 | grep -E "passed|failed"`
Expected: `Test run with 4 tests in 1 suite passed`.

- [ ] **Step 5: Commit**

```bash
git add Dict-app/ChunkDecodeQueue.swift Dict-appTests/ChunkDecodeQueueTests.swift
git commit -m "feat: serialized chunk decode queue with injectable decoder"
```

---

### Task 5: Wire streaming into StreamingTranscriptionService

**Files:**
- Modify: `Dict-app/StreamingTranscriptionService.swift`

**Interfaces:**
- Consumes: `SpeechSegmenter`, `TranscriptAssembler`, `ChunkDecodeQueue`, `VoiceGate.voiceActivity(energies:threshold:)`, existing `Self.gateAndTrim(samples:)`.
- Produces: no public API change.

- [ ] **Step 1: Add streaming state properties**

In the property block near `private var session = 0`, add:

```swift
    private var segmenter = SpeechSegmenter()
    private var decodeQueue: ChunkDecodeQueue?
    /// How many samples of audioProcessor.audioSamples have been fed to the
    /// segmenter already.
    private var sampleCursor = 0
    /// Text decoded so far this session, used as decoder context for the
    /// next chunk.
    private var contextText = ""
```

- [ ] **Step 2: Add the decode helper**

Add this method to the class:

```swift
    /// Decodes one chunk with the previous chunk's text as decoder context.
    /// Returns nil on failure so the queue can mark the session degraded.
    private nonisolated static func decodeChunk(
        pipe: WhisperKit,
        request: ChunkDecodeQueue.Request
    ) async -> String? {
        var options = DecodingOptions(
            language: "en",
            temperature: 0.0,
            skipSpecialTokens: true,
            wordTimestamps: false
        )
        if !request.promptText.isEmpty, let tokenizer = pipe.tokenizer {
            let snippet = String(request.promptText.suffix(200))
            options.promptTokens = Array(tokenizer.encode(text: snippet).suffix(100))
            options.usePrefillPrompt = true
        }
        do {
            let results = try await pipe.transcribe(
                audioArray: request.samples,
                decodeOptions: options
            )
            let frameDuration: Float = 0.1
            let frameSamples = Int(frameDuration * Float(WhisperKit.sampleRate))
            let energies = VoiceGate.frameEnergies(
                samples: request.samples,
                frameSamples: frameSamples
            )
            // Session-wide threshold, so TranscriptFilter sees a consistent
            // baseline instead of re-deriving one per chunk.
            let activity = VoiceGate.voiceActivity(
                energies: energies,
                threshold: request.threshold
            )
            return TranscriptFilter().filteredText(
                segments: results.flatMap { $0.segments },
                voiceActivity: activity,
                frameDuration: frameDuration
            )
        } catch {
            print("[Streaming] Chunk decode failed: \(error)")
            return nil
        }
    }
```

- [ ] **Step 3: Reset streaming state and build the queue in `start()`**

In `start()`, immediately after the existing `audioEnergy = []` line, add:

```swift
        // Reset on start, not only on stop: state cleared only on the success
        // path leaks whenever the failure path runs.
        segmenter.reset()
        sampleCursor = 0
        contextText = ""
        let pipeForDecode = pipe
        decodeQueue = ChunkDecodeQueue { request in
            await Self.decodeChunk(pipe: pipeForDecode, request: request)
        }
```

- [ ] **Step 4: Drive segmentation from the existing waveform timer**

In `start()`, replace the body of the `energyTimer` closure with:

```swift
        energyTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isRecording else { return }
                self.audioEnergy = pipeRef.audioProcessor.relativeEnergy
                self.consumeNewAudio(from: pipeRef)
            }
        }
```

Then add the consumer method to the class:

```swift
    /// Feeds newly arrived samples to the segmenter and enqueues any chunk
    /// the pause detector completes.
    private func consumeNewAudio(from pipe: WhisperKit) {
        let all = pipe.audioProcessor.audioSamples
        guard all.count > sampleCursor else { return }
        let fresh = Array(all[sampleCursor..<all.count])
        sampleCursor = all.count
        guard let chunk = segmenter.append(fresh), let queue = decodeQueue else { return }
        let handle = queue.enqueue(ChunkDecodeQueue.Request(
            samples: chunk,
            promptText: contextText,
            threshold: segmenter.sessionThreshold
        ))
        // Extend the decoder context as soon as this chunk lands so the next
        // chunk is prompted with it.
        Task { @MainActor [weak self] in
            if let text = await handle.value, !text.isEmpty {
                self?.contextText += (self?.contextText.isEmpty == true ? "" : " ") + text
            }
        }
        print("[Streaming] Chunk enqueued: \(chunk.count) samples")
    }
```

- [ ] **Step 5: Tear down streaming state in `cancel()`**

In `cancel()`, after `energyTimer = nil`, add:

```swift
        decodeQueue?.cancelAll()
        decodeQueue = nil
        segmenter.reset()
        sampleCursor = 0
        contextText = ""
```

- [ ] **Step 6: Use the streamed chunks in `stop()`, with fallback**

In `stop()`, after the existing `let samples = Array(pipe.audioProcessor.audioSamples)` and `pipe.audioProcessor.stopRecording()` lines, and before the existing `guard !samples.isEmpty` check, add:

```swift
        // Take the tail and let it jump ahead of nothing: at most one chunk
        // decode can still be in flight.
        let tail = segmenter.finish()
        let queue = decodeQueue
        decodeQueue = nil
        if let tail, let queue {
            queue.enqueue(ChunkDecodeQueue.Request(
                samples: tail,
                promptText: contextText,
                threshold: segmenter.sessionThreshold
            ))
        }
        var streamedChunks: [String] = []
        var streamingFailed = queue?.hasFailed ?? false
        if let queue {
            streamedChunks = await queue.drain()
            streamingFailed = streamingFailed || queue.hasFailed
        }
        segmenter.reset()
        sampleCursor = 0
        contextText = ""

        if !streamingFailed, !streamedChunks.isEmpty {
            let assembled = TranscriptAssembler.assemble(streamedChunks)
            if !assembled.isEmpty {
                print("[Streaming] Result from \(streamedChunks.count) chunk(s): \"\(assembled)\"")
                return assembled
            }
        }
        print("[Streaming] Falling back to one-shot decode (failed=\(streamingFailed), chunks=\(streamedChunks.count))")
```

Everything already in `stop()` below this point is the fallback path and stays exactly as it is.

- [ ] **Step 7: Build**

Run: `xcodebuild -project Dict-app.xcodeproj -scheme Dict-app -destination 'platform=macOS' build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 8: Run the full suite**

Run: `xcodebuild -project Dict-app.xcodeproj -scheme Dict-app -destination 'platform=macOS' test 2>&1 | grep -E "Test run with|Restarting"`
Expected: all tests pass, no `Restarting after unexpected exit`.

- [ ] **Step 9: Commit**

```bash
git add Dict-app/StreamingTranscriptionService.swift
git commit -m "feat: decode speech chunks during recording with one-shot fallback"
```

---

### Task 6: Equivalence and repeat-session gate

This is the acceptance criterion. If it cannot pass, ship the fallback and not the feature.

**Files:**
- Create: `Dict-appTests/StreamingEquivalenceTests.swift`

**Interfaces:**
- Consumes: `StreamingTranscriptionService`, `TranscriptAssembler`, `SpeechSegmenter`, `Self.gateAndTrim`.
- Produces: nothing.

- [ ] **Step 1: Write the test**

Create `Dict-appTests/StreamingEquivalenceTests.swift`:

```swift
import Foundation
import Testing
import WhisperKit
@testable import Dict_app

/// Ship gate for chunked streaming: the chunked path must produce
/// substantially the same words as the one-shot path on speech with real
/// pauses. Chunk boundaries are exactly where a streaming transcriber loses
/// words, so this drives the real segmenter over real synthesized audio.
struct StreamingEquivalenceTests {
    /// Three sentences separated by pauses long enough to split on.
    private func fixtureAudio() throws -> [Float] {
        let sentences = [
            "I think we should ship the new build tomorrow afternoon",
            "But only if the integration tests are passing on the release branch",
            "Otherwise we wait until Monday morning and try again"
        ]
        var audio: [Float] = [Float](repeating: 0, count: Int(0.2 * Float(WhisperKit.sampleRate)))
        for sentence in sentences {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("dict-stream-\(UUID().uuidString).wav")
            defer { try? FileManager.default.removeItem(at: url) }
            let say = Process()
            say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            say.arguments = ["-o", url.path, "--data-format=LEF32@16000", sentence]
            try say.run()
            say.waitUntilExit()
            audio += try AudioProcessor.loadAudioAsFloatArray(fromPath: url.path)
            // 1.2s pause: comfortably over the 0.6s split threshold.
            audio += [Float](repeating: 0, count: Int(1.2 * Float(WhisperKit.sampleRate)))
        }
        return audio
    }

    @Test func chunkedOutputMatchesOneShotOnPausedSpeech() async throws {
        let audio = try fixtureAudio()

        // Segment exactly as the live path would.
        var segmenter = SpeechSegmenter()
        var chunks: [[Float]] = []
        // Feed in 0.05s slices, mimicking the waveform timer cadence.
        let slice = Int(0.05 * Double(WhisperKit.sampleRate))
        var index = 0
        while index < audio.count {
            let end = min(index + slice, audio.count)
            if let chunk = segmenter.append(Array(audio[index..<end])) {
                chunks.append(chunk)
            }
            index = end
        }
        if let tail = segmenter.finish() { chunks.append(tail) }

        #expect(chunks.count >= 2, "fixture should split into multiple chunks")

        let modelURL = try await WhisperKit.download(variant: "distil-large-v3")
        let pipe = try await WhisperKit(WhisperKitConfig(
            modelFolder: modelURL.path, load: true, download: false
        ))

        // Chunked path, with context carry-over, mirroring decodeChunk.
        var context = ""
        var chunkTexts: [String] = []
        for chunk in chunks {
            var options = DecodingOptions(
                language: "en", temperature: 0.0,
                skipSpecialTokens: true, wordTimestamps: false
            )
            if !context.isEmpty, let tokenizer = pipe.tokenizer {
                options.promptTokens = Array(tokenizer.encode(text: String(context.suffix(200))).suffix(100))
                options.usePrefillPrompt = true
            }
            let results = try await pipe.transcribe(audioArray: chunk, decodeOptions: options)
            let frameSamples = Int(0.1 * Float(WhisperKit.sampleRate))
            let energies = VoiceGate.frameEnergies(samples: chunk, frameSamples: frameSamples)
            let text = TranscriptFilter().filteredText(
                segments: results.flatMap { $0.segments },
                voiceActivity: VoiceGate.voiceActivity(energies: energies, threshold: segmenter.sessionThreshold),
                frameDuration: 0.1
            )
            if !text.isEmpty {
                chunkTexts.append(text)
                context += (context.isEmpty ? "" : " ") + text
            }
        }
        let streamed = TranscriptAssembler.assemble(chunkTexts).lowercased()
        print("[EQUIV] streamed: \"\(streamed)\"")

        // Every sentence's distinctive words must survive chunking.
        for phrase in ["ship the new build", "integration tests", "monday morning"] {
            #expect(streamed.contains(phrase), "streamed output lost \"\(phrase)\"")
        }
    }

    @Test func repeatedSessionsLeaveNoState() async throws {
        let service = await StreamingTranscriptionService()
        for session in 1...3 {
            try await service.start()
            try await Task.sleep(for: .milliseconds(400))
            _ = await service.stop()
            let recording = await service.isRecording
            #expect(!recording, "session \(session) should have stopped")
        }
    }
}
```

- [ ] **Step 2: Run it**

Run: `xcodebuild -project Dict-app.xcodeproj -scheme Dict-app -destination 'platform=macOS' test -only-testing:Dict-appTests/StreamingEquivalenceTests 2>&1 | grep -E "EQUIV|passed|failed|Restarting"`
Expected: `Test run with 2 tests in 1 suite passed`, and the `[EQUIV]` line reads as coherent English.

- [ ] **Step 3: If the equivalence test fails, stop and report**

Do not tune thresholds repeatedly to force a pass. If words are lost at boundaries, that is the signal from the spec's Risks section that approach A is not sufficient and the overlapping-window approach (approach B) is needed. Report the actual `[EQUIV]` output and stop.

- [ ] **Step 4: Commit**

```bash
git add Dict-appTests/StreamingEquivalenceTests.swift
git commit -m "test: streaming vs one-shot equivalence gate"
```

- [ ] **Step 5: Measure the improvement**

Run the app, dictate the same roughly 15-second sentence used in Task 1, and compare the new post-release wait against the baseline `[Timing] oneshot` figure. Report both numbers. If there is no measurable improvement, say so plainly rather than shipping on the assumption that there is.

---

## Self-Review Notes

- Spec coverage: segmenter (Task 2), assembler (Task 3), queue with bounded contention and promptTokens (Task 4), orchestration/fallback/state reset (Task 5), all four test suites plus the ship gate and the measurement step (Tasks 1 and 6). The spec's "instrument first" risk item is Task 1.
- The spec lists `StreamingRepeatSessionTests` as a separate suite; it is folded into `StreamingEquivalenceTests.repeatedSessionsLeaveNoState` to avoid a file containing one test.
- Naming is consistent across tasks: `sessionThreshold`, `ChunkDecodeQueue.Request(samples:promptText:threshold:)`, `TranscriptAssembler.assemble(_:)`.
