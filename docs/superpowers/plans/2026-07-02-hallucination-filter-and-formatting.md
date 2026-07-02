# Hallucination Filter + On-Device Formatting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop Whisper from typing "Thank you." when the mic hears silence, and format transcripts (punctuation, paragraphs, filler removal) with Apple's on-device Foundation Models LLM.

**Architecture:** A layered deterministic filter runs at transcription time — an `EnergyVAD` gate skips/trims silent audio before Whisper sees it, then `TranscriptFilter` drops hallucinated segments using per-segment confidence and a VAD-guarded phrase blocklist. A separate `TranscriptFormatter` wraps a Foundation Models `LanguageModelSession` and rewrites the filtered transcript; every failure path returns the raw text unchanged.

**Tech Stack:** Swift, WhisperKit (already a dependency — provides `EnergyVAD`, `TranscriptionSegment`), FoundationModels (system framework, macOS 26+), Swift Testing (`import Testing`) in a new unit-test target.

**Spec:** `docs/superpowers/specs/2026-07-02-hallucination-filter-and-formatting-design.md`

## Global Constraints

- Deployment target: macOS 26.4; `SDKROOT = macosx`.
- The app target sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and `SWIFT_APPROACHABLE_CONCURRENCY = YES`; the new test target must match both.
- App module name for `@testable import` is `Dict_app` (product name `Dict-app`).
- No new third-party dependencies. FoundationModels is a system framework — no package or Frameworks-phase change needed.
- Foundation Models context window is 4,096 tokens total (instructions + prompt + output); a token ≈ 3-4 English characters.
- Any formatting failure (model unavailable, error, timeout, sanity-check failure) must fall back to inserting the raw filtered transcript. Dictation must never produce nothing because formatting failed.
- Dev team for code signing: `ZPU7B69KH3`.
- All `xcodebuild` commands run from the repo root `/Users/matt/Apps/Dict-app`.
- Commit after each task with the message given in the task.

---

### Task 1: Add a unit test target

The project has no test target. Add `Dict-appTests` (unit test bundle hosted in the app) by hand-editing the pbxproj — the project uses `objectVersion = 77` with `PBXFileSystemSynchronizedRootGroup`, so the test target gets its own synchronized folder and no per-file build entries.

**Files:**
- Create: `Dict-appTests/DictAppTests.swift`
- Modify: `Dict-app.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: a `Dict-appTests` target where `xcodebuild test -scheme Dict-app -destination 'platform=macOS'` runs Swift Testing tests that can `@testable import Dict_app`. All later tasks rely on this command.

- [ ] **Step 1: Create the test folder and a smoke test**

Create `Dict-appTests/DictAppTests.swift`:

```swift
import Testing
@testable import Dict_app

struct DictAppTests {
    @Test func smokeTest() {
        #expect(Bool(true))
    }
}
```

- [ ] **Step 2: Add the test target to project.pbxproj**

Six edits to `Dict-app.xcodeproj/project.pbxproj`. New object IDs all use the prefix `C9DD10xx2FB00000000000xx` (unique in this file).

**2a.** In the `PBXFileReference` section, after the `dict-icon.icon` line, add:

```
		C9DD10032FB0000000000003 /* Dict-appTests.xctest */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = "Dict-appTests.xctest"; sourceTree = BUILT_PRODUCTS_DIR; };
```

**2b.** In the `PBXFileSystemSynchronizedRootGroup` section, after the closing `};` of the `C95EB2C12F7FF45400B3F4AE /* Dict-app */` block, add:

```
		C9DD10012FB0000000000001 /* Dict-appTests */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			path = "Dict-appTests";
			sourceTree = "<group>";
		};
```

**2c.** In the main `PBXGroup` (`C95EB2B62F7FF45300B3F4AE`), add the tests group to `children` after the `Dict-app` entry:

```
				C9DD10012FB0000000000001 /* Dict-appTests */,
```

Also add the product to the `Products` group (`C95EB2C02F7FF45300B3F4AE`) children:

```
				C9DD10032FB0000000000003 /* Dict-appTests.xctest */,
```

**2d.** After the end of the existing `PBXNativeTarget` block for `Dict-app` (before `/* End PBXNativeTarget section */`), add the test target, its build phases, and dependency objects. Add these three new sections in full (the `PBXContainerItemProxy` and `PBXTargetDependency` sections don't exist yet — create them alphabetically: ContainerItemProxy after PBXBuildFile/FileReference sections region, TargetDependency after PBXSourcesBuildPhase; exact placement between sections does not matter to the parser, but keep each `/* Begin X section */ ... /* End X section */` pair intact):

```
/* Begin PBXContainerItemProxy section */
		C9DD10072FB0000000000007 /* PBXContainerItemProxy */ = {
			isa = PBXContainerItemProxy;
			containerPortal = C95EB2B72F7FF45300B3F4AE /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = C95EB2BE2F7FF45300B3F4AE;
			remoteInfo = "Dict-app";
		};
/* End PBXContainerItemProxy section */
```

Inside the `PBXNativeTarget` section, after the app target's block:

```
		C9DD10022FB0000000000002 /* Dict-appTests */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = C9DD10092FB0000000000009 /* Build configuration list for PBXNativeTarget "Dict-appTests" */;
			buildPhases = (
				C9DD10042FB0000000000004 /* Sources */,
				C9DD10052FB0000000000005 /* Frameworks */,
				C9DD10062FB0000000000006 /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
				C9DD10082FB0000000000008 /* PBXTargetDependency */,
			);
			fileSystemSynchronizedGroups = (
				C9DD10012FB0000000000001 /* Dict-appTests */,
			);
			name = "Dict-appTests";
			packageProductDependencies = (
			);
			productName = "Dict-appTests";
			productReference = C9DD10032FB0000000000003 /* Dict-appTests.xctest */;
			productType = "com.apple.product-type.bundle.unit-test";
		};
```

New section for the dependency:

```
/* Begin PBXTargetDependency section */
		C9DD10082FB0000000000008 /* PBXTargetDependency */ = {
			isa = PBXTargetDependency;
			target = C95EB2BE2F7FF45300B3F4AE /* Dict-app */;
			targetProxy = C9DD10072FB0000000000007 /* PBXContainerItemProxy */;
		};
/* End PBXTargetDependency section */
```

Build phases — add to the existing `PBXSourcesBuildPhase`, `PBXFrameworksBuildPhase`, and `PBXResourcesBuildPhase` sections respectively:

```
		C9DD10042FB0000000000004 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
```

```
		C9DD10052FB0000000000005 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
```

```
		C9DD10062FB0000000000006 /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
```

**2e.** In the `XCBuildConfiguration` section, after the app target's Release block (`C95EB2CE2F7FF45500B3F4AE`), add:

```
		C9DD100A2FB000000000000A /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				BUNDLE_LOADER = "$(TEST_HOST)";
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = ZPU7B69KH3;
				GENERATE_INFOPLIST_FILE = YES;
				MACOSX_DEPLOYMENT_TARGET = 26.4;
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = "birchtree.Dict-appTests";
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_APPROACHABLE_CONCURRENCY = YES;
				SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor;
				SWIFT_EMIT_LOC_STRINGS = NO;
				SWIFT_VERSION = 5.0;
				TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Dict-app.app/Contents/MacOS/Dict-app";
			};
			name = Debug;
		};
		C9DD100B2FB000000000000B /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				BUNDLE_LOADER = "$(TEST_HOST)";
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = ZPU7B69KH3;
				GENERATE_INFOPLIST_FILE = YES;
				MACOSX_DEPLOYMENT_TARGET = 26.4;
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = "birchtree.Dict-appTests";
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_APPROACHABLE_CONCURRENCY = YES;
				SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor;
				SWIFT_EMIT_LOC_STRINGS = NO;
				SWIFT_VERSION = 5.0;
				TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Dict-app.app/Contents/MacOS/Dict-app";
			};
			name = Release;
		};
```

In the `XCConfigurationList` section add:

```
		C9DD10092FB0000000000009 /* Build configuration list for PBXNativeTarget "Dict-appTests" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				C9DD100A2FB000000000000A /* Debug */,
				C9DD100B2FB000000000000B /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
```

**2f.** In the `PBXProject` block, add the new target to `targets`:

```
			targets = (
				C95EB2BE2F7FF45300B3F4AE /* Dict-app */,
				C9DD10022FB0000000000002 /* Dict-appTests */,
			);
```

- [ ] **Step 3: Verify the project still parses and lists both targets**

Run: `xcodebuild -list -project Dict-app.xcodeproj`
Expected: `Targets:` shows `Dict-app` and `Dict-appTests`. If this errors with "cannot be parsed", diff the pbxproj edits against this task — a missing semicolon or brace is the usual culprit.

- [ ] **Step 4: Run the test suite**

Run: `xcodebuild test -project Dict-app.xcodeproj -scheme Dict-app -destination 'platform=macOS' 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **` (the smoke test passes; the app briefly launches as test host, which is normal).
Fallback: if the auto-generated `Dict-app` scheme doesn't include the new test target, run `xcodebuild test -project Dict-app.xcodeproj -scheme Dict-appTests -destination 'platform=macOS' 2>&1 | tail -20` instead, and use that form in later tasks.

- [ ] **Step 5: Commit**

```bash
git add Dict-appTests Dict-app.xcodeproj/project.pbxproj
git commit -m "test: add Dict-appTests unit test target"
```

---

### Task 2: TranscriptFilter (hallucination segment filter)

Pure logic, TDD. Drops segments by no-speech confidence (OR logic — deliberately stricter than Whisper's built-in AND) and a VAD-guarded blocklist of known silence hallucinations.

**Files:**
- Create: `Dict-app/TranscriptFilter.swift`
- Test: `Dict-appTests/TranscriptFilterTests.swift`

**Interfaces:**
- Consumes: `TranscriptionSegment` from WhisperKit (`text: String`, `start/end: Float` seconds, `noSpeechProb: Float`, `avgLogprob: Float`; memberwise init has defaults for every field, in declaration order `id, seek, start, end, text, tokens, tokenLogProbs, temperature, avgLogprob, compressionRatio, noSpeechProb, words`).
- Produces: `struct TranscriptFilter` with `func filteredText(segments: [TranscriptionSegment], voiceActivity: [Bool], frameDuration: Float) -> String` and `static func normalize(_ text: String) -> String`. Task 3 calls `filteredText`.

- [ ] **Step 1: Write the failing tests**

Create `Dict-appTests/TranscriptFilterTests.swift`:

```swift
import Testing
import WhisperKit
@testable import Dict_app

struct TranscriptFilterTests {
    let filter = TranscriptFilter()

    private func segment(
        _ text: String,
        start: Float = 0,
        end: Float = 2,
        noSpeechProb: Float = 0.1
    ) -> TranscriptionSegment {
        TranscriptionSegment(start: start, end: end, text: text, noSpeechProb: noSpeechProb)
    }

    // 20 frames at 0.1s = 2 seconds of audio
    private let allVoiced = [Bool](repeating: true, count: 20)
    private let allSilent = [Bool](repeating: false, count: 20)

    @Test func keepsNormalSpeech() {
        let text = filter.filteredText(
            segments: [segment(" Hello world.")],
            voiceActivity: allVoiced,
            frameDuration: 0.1
        )
        #expect(text == "Hello world.")
    }

    @Test func dropsHighNoSpeechProbEvenOverVoicedAudio() {
        let text = filter.filteredText(
            segments: [segment("Anything at all.", noSpeechProb: 0.8)],
            voiceActivity: allVoiced,
            frameDuration: 0.1
        )
        #expect(text.isEmpty)
    }

    @Test func dropsBlocklistPhraseOverSilence() {
        let text = filter.filteredText(
            segments: [segment(" Thank you.")],
            voiceActivity: allSilent,
            frameDuration: 0.1
        )
        #expect(text.isEmpty)
    }

    @Test func keepsBlocklistPhraseOverRealSpeech() {
        let text = filter.filteredText(
            segments: [segment(" Thank you.")],
            voiceActivity: allVoiced,
            frameDuration: 0.1
        )
        #expect(text == "Thank you.")
    }

    @Test func keepsNonBlocklistTextOverSilentVAD() {
        // Quiet-but-real speech the VAD missed must not be eaten
        // unless it is a known hallucination phrase.
        let text = filter.filteredText(
            segments: [segment("The meeting is at noon.")],
            voiceActivity: allSilent,
            frameDuration: 0.1
        )
        #expect(text == "The meeting is at noon.")
    }

    @Test func normalizationStripsPunctuationAndCase() {
        #expect(TranscriptFilter.normalize(" Thank You!!! ") == "thank you")
        #expect(TranscriptFilter.normalize("Thanks for watching.") == "thanks for watching")
    }

    @Test func joinsKeptSegmentsWithSingleSpaces() {
        let text = filter.filteredText(
            segments: [
                segment(" First part.", start: 0, end: 1),
                segment(" Second part.", start: 1, end: 2),
            ],
            voiceActivity: allVoiced,
            frameDuration: 0.1
        )
        #expect(text == "First part. Second part.")
    }

    @Test func blocklistChecksOnlyTheSegmentsOwnTimeWindow() {
        // Speech in frames 0..<10, silence in 10..<20. A "Thank you."
        // hallucinated during the silent tail must be dropped even though
        // the recording contains speech elsewhere.
        let halfVoiced = [Bool](repeating: true, count: 10) + [Bool](repeating: false, count: 10)
        let text = filter.filteredText(
            segments: [
                segment(" Hello there.", start: 0, end: 1),
                segment(" Thank you.", start: 1, end: 2),
            ],
            voiceActivity: halfVoiced,
            frameDuration: 0.1
        )
        #expect(text == "Hello there.")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Dict-app.xcodeproj -scheme Dict-app -destination 'platform=macOS' 2>&1 | tail -20`
Expected: BUILD FAILED — `cannot find 'TranscriptFilter' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Dict-app/TranscriptFilter.swift`:

```swift
import Foundation
import WhisperKit

/// Drops Whisper segments that are likely silence hallucinations ("Thank
/// you.", "Thanks for watching!", …). Two layered rules, both deliberately
/// stricter than Whisper's built-in AND of noSpeechProb and avgLogprob,
/// which confident hallucinations slip through.
struct TranscriptFilter {
    /// Segments with noSpeechProb above this are dropped outright.
    var noSpeechThreshold: Float = 0.5
    /// Blocklisted phrases are dropped when less than this fraction of
    /// their audio frames contain voice activity.
    var minVoicedFraction: Float = 0.2

    /// Phrases Whisper is known to decode from silence, in normalized form.
    static let hallucinationPhrases: Set<String> = [
        "thank you", "thanks", "thank you very much", "thank you so much",
        "thanks for watching", "thank you for watching",
        "thanks for listening", "thank you for listening",
        "see you next time", "see you in the next video",
        "bye", "bye bye", "goodbye",
        "the end", "you", "so", "subscribe", "please subscribe",
    ]

    /// - Parameters:
    ///   - segments: Whisper output; times are relative to the audio that
    ///     was transcribed.
    ///   - voiceActivity: per-frame VAD flags for that same audio.
    ///   - frameDuration: seconds per VAD frame.
    func filteredText(
        segments: [TranscriptionSegment],
        voiceActivity: [Bool],
        frameDuration: Float
    ) -> String {
        segments
            .filter { keep($0, voiceActivity: voiceActivity, frameDuration: frameDuration) }
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func keep(
        _ segment: TranscriptionSegment,
        voiceActivity: [Bool],
        frameDuration: Float
    ) -> Bool {
        if segment.noSpeechProb > noSpeechThreshold {
            print("[Filter] Dropped (noSpeechProb \(segment.noSpeechProb)): \"\(segment.text)\"")
            return false
        }
        let normalized = Self.normalize(segment.text)
        if normalized.isEmpty { return false }
        if Self.hallucinationPhrases.contains(normalized) {
            let voiced = voicedFraction(
                start: segment.start,
                end: segment.end,
                voiceActivity: voiceActivity,
                frameDuration: frameDuration
            )
            if voiced < minVoicedFraction {
                print("[Filter] Dropped (blocklist, voiced \(voiced)): \"\(segment.text)\"")
                return false
            }
        }
        return true
    }

    /// Lowercased, punctuation stripped, whitespace collapsed — the form
    /// used for blocklist matching.
    static func normalize(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Fraction of VAD frames overlapping [start, end] that contain voice.
    private func voicedFraction(
        start: Float,
        end: Float,
        voiceActivity: [Bool],
        frameDuration: Float
    ) -> Float {
        guard frameDuration > 0, !voiceActivity.isEmpty, end > start else { return 0 }
        let first = max(0, Int(start / frameDuration))
        let last = min(voiceActivity.count - 1, Int((end / frameDuration).rounded(.up)) - 1)
        guard first <= last else { return 0 }
        let window = voiceActivity[first...last]
        return Float(window.count(where: { $0 })) / Float(window.count)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project Dict-app.xcodeproj -scheme Dict-app -destination 'platform=macOS' 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`, all `TranscriptFilterTests` pass.

- [ ] **Step 5: Commit**

```bash
git add Dict-app/TranscriptFilter.swift Dict-appTests/TranscriptFilterTests.swift
git commit -m "feat: filter Whisper silence hallucinations from transcript segments"
```

---

### Task 3: VAD gate + silence trim in the transcription service

Add `VoiceGate` (pure trim-range logic, TDD) and wire the VAD gate, trimming, and `TranscriptFilter` into `StreamingTranscriptionService.stop()`.

**Files:**
- Create: `Dict-app/VoiceGate.swift`
- Test: `Dict-appTests/VoiceGateTests.swift`
- Modify: `Dict-app/StreamingTranscriptionService.swift:79-119` (the `stop()` method)

**Interfaces:**
- Consumes: `TranscriptFilter.filteredText(segments:voiceActivity:frameDuration:)` from Task 2; WhisperKit's `EnergyVAD(sampleRate:frameLength:frameOverlap:energyThreshold:)` with `voiceActivity(in: [Float]) -> [Bool]` (one flag per frame); `pipe.transcribe(audioArray:decodeOptions:) -> [TranscriptionResult]`, each result carrying `.segments: [TranscriptionSegment]`.
- Produces: `enum VoiceGate` with `static func activeFrameRange(voiceActivity: [Bool], paddingFrames: Int) -> Range<Int>?`. `stop()` keeps its existing signature `func stop() async -> String` — no caller changes.

- [ ] **Step 1: Write the failing tests**

Create `Dict-appTests/VoiceGateTests.swift`:

```swift
import Testing
@testable import Dict_app

struct VoiceGateTests {
    @Test func returnsNilForPureSilence() {
        let range = VoiceGate.activeFrameRange(
            voiceActivity: [Bool](repeating: false, count: 50),
            paddingFrames: 3
        )
        #expect(range == nil)
    }

    @Test func returnsNilForEmptyInput() {
        #expect(VoiceGate.activeFrameRange(voiceActivity: [], paddingFrames: 3) == nil)
    }

    @Test func padsAroundVoicedRegion() {
        // Voice in frames 10...19 of 50, padding 3 → 7..<23
        var frames = [Bool](repeating: false, count: 50)
        for i in 10...19 { frames[i] = true }
        let range = VoiceGate.activeFrameRange(voiceActivity: frames, paddingFrames: 3)
        #expect(range == 7..<23)
    }

    @Test func clampsPaddingAtBothEdges() {
        // Voice in frames 1...48 of 50, padding 3 → clamped to 0..<50
        var frames = [Bool](repeating: false, count: 50)
        for i in 1...48 { frames[i] = true }
        let range = VoiceGate.activeFrameRange(voiceActivity: frames, paddingFrames: 3)
        #expect(range == 0..<50)
    }

    @Test func spansFromFirstToLastVoiceAcrossGaps() {
        // Voice at frames 5 and 40 with silence between: one padded span.
        var frames = [Bool](repeating: false, count: 50)
        frames[5] = true
        frames[40] = true
        let range = VoiceGate.activeFrameRange(voiceActivity: frames, paddingFrames: 2)
        #expect(range == 3..<43)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Dict-app.xcodeproj -scheme Dict-app -destination 'platform=macOS' 2>&1 | tail -20`
Expected: BUILD FAILED — `cannot find 'VoiceGate' in scope`.

- [ ] **Step 3: Implement VoiceGate**

Create `Dict-app/VoiceGate.swift`:

```swift
import Foundation

/// Pure logic for gating and trimming a recording based on per-frame
/// voice-activity flags.
enum VoiceGate {
    /// The frame range spanning first-to-last voice activity, padded on
    /// both sides and clamped to the buffer. Nil when no frame has voice —
    /// the caller should skip transcription entirely.
    static func activeFrameRange(voiceActivity: [Bool], paddingFrames: Int) -> Range<Int>? {
        guard let first = voiceActivity.firstIndex(of: true),
              let last = voiceActivity.lastIndex(of: true) else {
            return nil
        }
        let start = max(0, first - paddingFrames)
        let end = min(voiceActivity.count, last + 1 + paddingFrames)
        return start..<end
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project Dict-app.xcodeproj -scheme Dict-app -destination 'platform=macOS' 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Wire the gate, trim, and filter into stop()**

In `Dict-app/StreamingTranscriptionService.swift`, replace the body of `stop()` from the `guard !samples.isEmpty` check through the end of the `do` block with:

```swift
        guard !samples.isEmpty else {
            print("[Transcription] No samples captured")
            return ""
        }

        // VAD gate: if the recording contains no detectable voice, skip
        // Whisper entirely — decoding pure silence is what produces
        // "Thank you." hallucinations.
        let frameDuration: Float = 0.1
        let frameSamples = Int(frameDuration * Float(WhisperKit.sampleRate))
        let vad = EnergyVAD(
            sampleRate: WhisperKit.sampleRate,
            frameLength: frameDuration,
            frameOverlap: 0,
            energyThreshold: 0.02
        )
        let voiceActivity = vad.voiceActivity(in: samples)
        guard let frameRange = VoiceGate.activeFrameRange(voiceActivity: voiceActivity, paddingFrames: 3) else {
            print("[Transcription] No voice activity detected, skipping transcription")
            return ""
        }

        // Trim leading/trailing silence (keeping 0.3s padding) so Whisper
        // never decodes long silent stretches at the edges.
        let sampleStart = frameRange.lowerBound * frameSamples
        let sampleEnd = min(samples.count, frameRange.upperBound * frameSamples)
        let trimmedSamples = Array(samples[sampleStart..<sampleEnd])
        let trimmedVoiceActivity = Array(voiceActivity[frameRange])
        print("[Transcription] Trimmed \(samples.count) samples to \(trimmedSamples.count)")

        do {
            let options = DecodingOptions(
                language: "en",
                temperature: 0.0,
                skipSpecialTokens: true,
                wordTimestamps: false
            )
            let results = try await pipe.transcribe(
                audioArray: trimmedSamples,
                decodeOptions: options
            )
            let segments = results.flatMap { $0.segments }
            let text = TranscriptFilter().filteredText(
                segments: segments,
                voiceActivity: trimmedVoiceActivity,
                frameDuration: frameDuration
            )
            print("[Transcription] Result: \"\(text)\"")
            return text
        } catch {
            print("[Transcription] Failed: \(error)")
            return ""
        }
```

- [ ] **Step 6: Build and run the full test suite**

Run: `xcodebuild test -project Dict-app.xcodeproj -scheme Dict-app -destination 'platform=macOS' 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **` (build proves the WhisperKit API usage compiles; behavior is covered by the manual checks in Task 5).

- [ ] **Step 7: Commit**

```bash
git add Dict-app/VoiceGate.swift Dict-appTests/VoiceGateTests.swift Dict-app/StreamingTranscriptionService.swift
git commit -m "feat: gate and trim recordings with VAD before transcription"
```

---

### Task 4: TranscriptFormatter (Foundation Models)

Chunking and sanity-check helpers TDD'd; the model call itself is guarded by availability check, timeout, and the sanity check, with every failure returning the input unchanged.

**Files:**
- Create: `Dict-app/TranscriptFormatter.swift`
- Test: `Dict-appTests/TranscriptFormatterTests.swift`

**Interfaces:**
- Consumes: FoundationModels — `SystemLanguageModel.default.availability == .available`, `LanguageModelSession(instructions: String)`, `try await session.respond(to: prompt).content` (String), `GenerationOptions(temperature:)`.
- Produces: `final class TranscriptFormatter` with `func format(_ raw: String) async -> String` (never throws, never returns empty for non-empty input), plus testable statics `chunked(_ text: String, maxWords: Int) -> [String]` and `isAcceptable(input: String, output: String) -> Bool`. Task 5 calls `format`.

- [ ] **Step 1: Write the failing tests**

Create `Dict-appTests/TranscriptFormatterTests.swift`:

```swift
import Testing
@testable import Dict_app

struct TranscriptFormatterTests {
    // MARK: chunked

    @Test func shortTextIsASingleChunk() {
        let text = "Hello world. This is short."
        #expect(TranscriptFormatter.chunked(text, maxWords: 700) == [text])
    }

    @Test func longTextSplitsOnSentenceBoundariesUnderMaxWords() {
        // 100 sentences x 10 words = 1000 words
        let sentence = "One two three four five six seven eight nine ten."
        let text = [String](repeating: sentence, count: 100).joined(separator: " ")
        let chunks = TranscriptFormatter.chunked(text, maxWords: 700)

        #expect(chunks.count == 2)
        for chunk in chunks {
            #expect(chunk.split(separator: " ").count <= 700)
            // Sentence boundaries respected: every chunk ends with a period.
            #expect(chunk.hasSuffix("."))
        }
        // No words lost.
        let totalWords = chunks.map { $0.split(separator: " ").count }.reduce(0, +)
        #expect(totalWords == 1000)
    }

    // MARK: isAcceptable

    @Test func acceptsOutputWithModestFillerRemoval() {
        let input = [String](repeating: "word", count: 100).joined(separator: " ")
        let output = [String](repeating: "word", count: 85).joined(separator: " ")
        #expect(TranscriptFormatter.isAcceptable(input: input, output: output))
    }

    @Test func rejectsEmptyOutput() {
        #expect(!TranscriptFormatter.isAcceptable(input: "some real words here", output: ""))
    }

    @Test func rejectsOutputThatAteContent() {
        let input = [String](repeating: "word", count: 100).joined(separator: " ")
        let output = [String](repeating: "word", count: 50).joined(separator: " ")
        #expect(!TranscriptFormatter.isAcceptable(input: input, output: output))
    }

    @Test func rejectsOutputThatAddedContent() {
        let input = [String](repeating: "word", count: 100).joined(separator: " ")
        let output = [String](repeating: "word", count: 160).joined(separator: " ")
        #expect(!TranscriptFormatter.isAcceptable(input: input, output: output))
    }

    // MARK: format fallback

    @Test func formatReturnsInputWhenInputIsBlank() async {
        let formatter = TranscriptFormatter()
        let result = await formatter.format("   ")
        #expect(result == "   ")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Dict-app.xcodeproj -scheme Dict-app -destination 'platform=macOS' 2>&1 | tail -20`
Expected: BUILD FAILED — `cannot find 'TranscriptFormatter' in scope`.

- [ ] **Step 3: Implement TranscriptFormatter**

Create `Dict-app/TranscriptFormatter.swift`:

```swift
import Foundation
import FoundationModels

enum TranscriptFormatterError: Error {
    case timedOut
}

/// Formats a raw dictation transcript with the on-device Foundation Models
/// LLM: punctuation, capitalization, paragraph breaks, filler-word removal,
/// and stitched self-corrections. Every failure path (model unavailable,
/// error, timeout, sanity-check failure) returns the input unchanged —
/// formatting must never block dictation output.
final class TranscriptFormatter {
    static let instructions = """
        You clean up raw dictation transcripts. Rewrite the user's text with:
        - Correct punctuation and capitalization.
        - Paragraph breaks (a blank line) where the topic or thought clearly shifts.
        - Filler words removed ("um", "uh", "you know", "like" when used as filler).
        - Obvious self-corrections stitched together: "send it Tuesday, no, \
        Wednesday" becomes "send it Wednesday".

        Never add new content, never reword or summarize, never answer \
        questions that appear in the text. Keep every technical term, name, \
        and number exactly as spoken. Output only the cleaned-up text with \
        no preamble or commentary.
        """

    /// The on-device model's 4,096-token window is shared by instructions,
    /// prompt, and output (output ≈ input size for this task), so cap
    /// chunks well below half the window.
    static let maxChunkWords = 700

    private let timeoutSeconds: UInt64 = 15

    func format(_ raw: String) async -> String {
        let input = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return raw }

        guard SystemLanguageModel.default.availability == .available else {
            print("[Formatter] Model unavailable, using raw transcript")
            return raw
        }

        do {
            var formattedChunks: [String] = []
            for chunk in Self.chunked(input, maxWords: Self.maxChunkWords) {
                let formatted = try await respondWithTimeout(to: chunk)
                formattedChunks.append(formatted.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            let output = formattedChunks.joined(separator: "\n\n")
            guard Self.isAcceptable(input: input, output: output) else {
                print("[Formatter] Output failed sanity check, using raw transcript")
                return raw
            }
            return output
        } catch {
            print("[Formatter] Failed (\(error)), using raw transcript")
            return raw
        }
    }

    /// One fresh single-turn session per chunk, raced against a timeout so
    /// a hung model call can't stall dictation indefinitely.
    private func respondWithTimeout(to chunk: String) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                let session = LanguageModelSession(instructions: Self.instructions)
                let options = GenerationOptions(temperature: 0.1)
                return try await session.respond(to: chunk, options: options).content
            }
            group.addTask { [timeoutSeconds] in
                try await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
                throw TranscriptFormatterError.timedOut
            }
            guard let first = try await group.next() else {
                throw TranscriptFormatterError.timedOut
            }
            group.cancelAll()
            return first
        }
    }

    /// Splits text into chunks of at most `maxWords`, breaking only on
    /// sentence boundaries. A single sentence longer than `maxWords`
    /// becomes its own oversized chunk (vanishingly rare in dictation).
    static func chunked(_ text: String, maxWords: Int) -> [String] {
        guard text.split(separator: " ").count > maxWords else { return [text] }

        var sentences: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { substring, _, _, _ in
            if let sentence = substring?.trimmingCharacters(in: .whitespacesAndNewlines),
               !sentence.isEmpty {
                sentences.append(sentence)
            }
        }
        if sentences.isEmpty { sentences = [text] }

        var chunks: [String] = []
        var current: [String] = []
        var currentWords = 0
        for sentence in sentences {
            let words = sentence.split(separator: " ").count
            if currentWords + words > maxWords, !current.isEmpty {
                chunks.append(current.joined(separator: " "))
                current = []
                currentWords = 0
            }
            current.append(sentence)
            currentWords += words
        }
        if !current.isEmpty {
            chunks.append(current.joined(separator: " "))
        }
        return chunks
    }

    /// The formatter may remove fillers but must not eat or invent content:
    /// reject output outside 75%–125% (+10 words slack for short inputs)
    /// of the input's word count, or empty output.
    static func isAcceptable(input: String, output: String) -> Bool {
        let inWords = input.split(separator: " ").count
        let outWords = output.split(separator: " ").count
        guard outWords > 0 else { return false }
        return Float(outWords) >= Float(inWords) * 0.75
            && Float(outWords) <= Float(inWords) * 1.25 + 10
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project Dict-app.xcodeproj -scheme Dict-app -destination 'platform=macOS' 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`, all `TranscriptFormatterTests` pass.

- [ ] **Step 5: Commit**

```bash
git add Dict-app/TranscriptFormatter.swift Dict-appTests/TranscriptFormatterTests.swift
git commit -m "feat: format transcripts with on-device Foundation Models LLM"
```

---

### Task 5: Pipeline integration + end-to-end verification

Wire the formatter into `PipelineCoordinator` between transcription and history-save/insertion, then verify the whole feature manually in the running app.

**Files:**
- Modify: `Dict-app/PipelineCoordinator.swift`

**Interfaces:**
- Consumes: `TranscriptFormatter.format(_:) async -> String` from Task 4; `StreamingTranscriptionService.stop() async -> String` from Task 3.
- Produces: `stopRecordingAndProcess() async -> String?` keeps its existing signature (callers in MenuBarManager/KeyMonitor unchanged); history now stores the formatted text that was actually typed.

- [ ] **Step 1: Insert the formatting pass**

Replace the body of `stopRecordingAndProcess()` in `Dict-app/PipelineCoordinator.swift` and add the formatter property:

```swift
@MainActor
final class PipelineCoordinator {
    let transcriptionService = StreamingTranscriptionService()
    let textInsertionService = TextInsertionService()
    let historyStore = HistoryStore()
    private let formatter = TranscriptFormatter()

    func startRecording() {
        Task {
            do {
                try await transcriptionService.start()
                print("[Pipeline] Streaming session started")
            } catch {
                print("[Pipeline] Failed to start streaming: \(error)")
            }
        }
    }

    func stopRecordingAndProcess() async -> String? {
        let rawText = await transcriptionService.stop()

        guard !rawText.isEmpty else {
            print("[Pipeline] No text produced, aborting")
            return nil
        }

        let text = await formatter.format(rawText)

        historyStore.save(cleanedText: text)
        print("[Pipeline] Saved to history. Inserting text...")
        await textInsertionService.insertText(text)
        print("[Pipeline] Text inserted")

        return text
    }
}
```

- [ ] **Step 2: Run the full test suite and build**

Run: `xcodebuild test -project Dict-app.xcodeproj -scheme Dict-app -destination 'platform=macOS' 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Dict-app/PipelineCoordinator.swift
git commit -m "feat: run transcripts through on-device formatting before insertion"
```

- [ ] **Step 4: Manual end-to-end verification (requires the human)**

Launch the app (`xcodebuild -project Dict-app.xcodeproj -scheme Dict-app -configuration Debug build` then run the built app, or run from Xcode) and check, watching the console output for `[Filter]`/`[Formatter]` lines:

1. **Silence:** start recording, say nothing for ~10s, stop. Expected: nothing typed, log shows "No voice activity detected".
2. **Speech then trailing silence:** dictate a sentence, stay silent ~10s, stop. Expected: the sentence is typed, no trailing "Thank you."
3. **Genuine "thank you":** dictate "Thanks for your help with this, thank you." Expected: it survives.
4. **Formatting:** dictate several sentences with "um"s across two topics. Expected: punctuation and capitalization corrected, fillers gone, a paragraph break at the topic shift.
5. **Fallback:** if Apple Intelligence is disabled on the machine, output is the raw transcript and the log says "Model unavailable".

Record the results; tune `energyThreshold` (0.02), `noSpeechThreshold` (0.5), or `minVoicedFraction` (0.2) only if a check fails.
