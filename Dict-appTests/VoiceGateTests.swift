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
