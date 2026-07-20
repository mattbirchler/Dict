import Testing
@testable import Dict_app

struct SpeechSegmentAccumulatorTests {
    private func makeSegmenter() -> SpeechSegmentAccumulator {
        SpeechSegmentAccumulator(
            sampleRate: 10,
            silenceThreshold: 0.003,
            silenceDuration: 0.3,
            minimumSegmentDuration: 0.5
        )
    }

    @Test func emitsAfterEnoughTrailingSilence() throws {
        var segmenter = makeSegmenter()
        let leadingSilence: [Float] = [0, 0]
        let speech: [Float] = [0.01, 0.01, 0.01]

        #expect(segmenter.append(leadingSilence) == nil)
        #expect(segmenter.append(speech) == nil)
        #expect(segmenter.append([0, 0]) == nil)

        let result = segmenter.append([0])
        let completed = try #require(result)
        #expect(completed == leadingSilence + speech + [0, 0, 0])
    }

    @Test func speechAfterShortPauseKeepsTheSegmentOpen() throws {
        var segmenter = makeSegmenter()

        #expect(segmenter.append([0.01, 0.01, 0.01]) == nil)
        #expect(segmenter.append([0, 0]) == nil)
        #expect(segmenter.append([0.01, 0.01]) == nil)
        #expect(segmenter.append([0, 0]) == nil)

        let result = segmenter.append([0])
        let completed = try #require(result)
        #expect(completed == [0.01, 0.01, 0.01, 0, 0, 0.01, 0.01, 0, 0, 0])
    }

    @Test func leadingSilenceAloneNeverCreatesASegment() {
        var segmenter = makeSegmenter()

        #expect(segmenter.append([Float](repeating: 0, count: 10)) == nil)
        #expect(segmenter.finish() == nil)
    }

    @Test func isolatedVoiceFramesStayTogetherUntilGateMinimumIsMet() throws {
        var segmenter = makeSegmenter()

        #expect(segmenter.append([0.01]) == nil)
        #expect(segmenter.append([0, 0, 0]) == nil)
        #expect(segmenter.append([0.01]) == nil)
        #expect(segmenter.append([0, 0]) == nil)

        let result = segmenter.append([0])
        let completed = try #require(result)
        #expect(completed == [0.01, 0, 0, 0, 0.01, 0, 0, 0])
    }

    @Test func finishReturnsTheUnsplittableFinalTail() throws {
        var segmenter = makeSegmenter()
        let finalTail: [Float] = [0, 0.01, 0.01, 0.01, 0]

        #expect(segmenter.append(finalTail) == nil)
        let result = segmenter.finish()
        #expect(try #require(result) == finalTail)
        #expect(segmenter.finish() == nil)
    }

    @Test func productionSegmentingFeedsEverySpokenRegionIntoTheGate() throws {
        let sampleRate = 16_000
        let speech = [Float](repeating: 0.01, count: sampleRate * 2)
        let pause = [Float](repeating: 0, count: sampleRate)
        let recording = speech + pause + speech
        var segmenter = SpeechSegmentAccumulator(sampleRate: sampleRate)
        var segments: [[Float]] = []

        for start in stride(from: 0, to: recording.count, by: 1_600) {
            let end = min(start + 1_600, recording.count)
            if let completed = segmenter.append(Array(recording[start..<end])) {
                segments.append(completed)
            }
        }
        if let final = segmenter.finish() {
            segments.append(final)
        }

        #expect(segments.count == 2)
        #expect(segments.flatMap { $0 } == recording)
        for segment in segments {
            #expect(StreamingTranscriptionService.gateAndTrim(samples: segment) != nil)
        }
    }
}
