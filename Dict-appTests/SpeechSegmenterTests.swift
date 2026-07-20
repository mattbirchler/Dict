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
