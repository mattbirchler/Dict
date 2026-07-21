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
    private func tone(amplitude: Float, seconds: Double) -> [Float] {
        [Float](repeating: amplitude, count: Int(Double(WhisperKit.sampleRate) * seconds))
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

    @Test func sessionThresholdSurvivesChunkBoundaryAndResetClearsIt() {
        var s = SpeechSegmenter()

        // First chunk: loud speech long enough to force a natural split
        // once the trailing silence exceeds 0.6s.
        #expect(s.append(voiced(seconds: 5.0)) == nil)
        let firstChunk = s.append(silent(seconds: 1.0))
        #expect(firstChunk != nil) // confirms the boundary was really crossed

        // Second chunk, appended after the split: much quieter but still
        // above the absolute floor, and long enough that its own frames
        // would outnumber the first chunk's if the threshold only looked
        // at this chunk in isolation.
        let quieterChunk = tone(amplitude: 0.01, seconds: 20.0)
        _ = s.append(quieterChunk)
        let sessionWideThreshold = s.sessionThreshold

        // A segmenter that only ever saw the quieter second chunk has no
        // memory of the louder first chunk's energies.
        var freshOnSecondChunkOnly = SpeechSegmenter()
        _ = freshOnSecondChunkOnly.append(quieterChunk)
        let secondChunkOnlyThreshold = freshOnSecondChunkOnly.sessionThreshold

        // If the chunk boundary had reset `energies`, these would be equal.
        // Instead the accumulated session is still shaped by the louder
        // first chunk, pulling the threshold above both what the quiet
        // chunk alone would produce and the absolute floor.
        #expect(sessionWideThreshold > secondChunkOnlyThreshold)
        #expect(sessionWideThreshold > VoiceGate.absoluteFloor)

        // reset() is the only thing that clears the session-wide energies.
        s.reset()
        #expect(s.sessionThreshold == VoiceGate.absoluteFloor)
    }
}
