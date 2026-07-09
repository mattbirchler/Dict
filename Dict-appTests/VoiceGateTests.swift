import Testing
@testable import Dict_app

struct VoiceGateTests {
    // MARK: voiceActivity (adaptive threshold)
    // Energy levels below are real measurements from this machine's mic:
    // room-noise floor ≈ 0.0015 RMS, normal speech peaks ≈ 0.005–0.010 RMS.

    @Test func detectsQuietSpeechAboveOwnNoiseFloor() {
        // Regression: fixed 0.02 threshold rejected every frame of real
        // speech. Floor 0.0015 with speech frames at 0.008 must be voiced.
        var energies = [Float](repeating: 0.0015, count: 30)
        for i in 10...20 { energies[i] = 0.008 }
        let activity = VoiceGate.voiceActivity(energies: energies)
        #expect(activity[15])
        #expect(activity.count(where: { $0 }) == 11)
        #expect(!activity[5])
    }

    @Test func rejectsSteadyRoomNoise() {
        // Real silence profile: floor ~0.0014, drifting up to 0.0025.
        let energies: [Float] = (0..<40).map { 0.0012 + Float($0 % 5) * 0.0003 }
        let activity = VoiceGate.voiceActivity(energies: energies)
        #expect(activity.allSatisfy { !$0 })
    }

    @Test func singleClickInSilenceIsNotEnoughForTheGate() {
        // Real silence recording had one 0.04 RMS click frame. voiceActivity
        // marks it, but the gate's minVoicedFrames=2 rejects the recording.
        var energies = [Float](repeating: 0.0014, count: 36)
        energies[7] = 0.04
        let activity = VoiceGate.voiceActivity(energies: energies)
        #expect(activity.count(where: { $0 }) == 1)
        let range = VoiceGate.activeFrameRange(
            voiceActivity: activity,
            paddingFrames: 3,
            minVoicedFrames: 2
        )
        #expect(range == nil)
    }

    @Test func stillDetectsLoudSpeech() {
        var energies = [Float](repeating: 0.001, count: 30)
        for i in 5...25 { energies[i] = 0.05 }
        let activity = VoiceGate.voiceActivity(energies: energies)
        #expect(activity.count(where: { $0 }) == 21)
    }

    @Test func deadSilentRoomStaysBelowAbsoluteFloor() {
        // Near-zero energies: relative rule alone would mark tiny wobbles
        // as voice; the absolute floor must keep everything unvoiced.
        let energies: [Float] = (0..<30).map { 0.0002 + Float($0 % 3) * 0.0002 }
        let activity = VoiceGate.voiceActivity(energies: energies)
        #expect(activity.allSatisfy { !$0 })
    }

    @Test func continuousSpeechKeepsSoftTrailingWords() {
        // Push-to-talk regression: the user talks for nearly the whole
        // recording, so the 25th-percentile "noise floor" lands on speech
        // energy and 3× that puts the threshold above everything but the
        // loudest peaks — trimming away the final, softer-spoken words.
        // 6 frames lead-in silence, 42 frames of speech with loud peaks,
        // 8 frames of soft trailing speech, 4 frames of release gap.
        var energies = [Float](repeating: 0.0015, count: 6)
        energies += (0..<42).map { [0.006, 0.009, 0.012, 0.02][$0 % 4] }
        energies += [Float](repeating: 0.005, count: 8)
        energies += [Float](repeating: 0.0015, count: 4)

        let activity = VoiceGate.voiceActivity(energies: energies)

        // The soft trailing words (frames 48...55) must count as voice so
        // the trim doesn't cut them off.
        #expect(activity[48...55].allSatisfy { $0 })
        // Lead-in and release-gap silence must stay unvoiced.
        #expect(activity[0...5].allSatisfy { !$0 })
        #expect(activity[56...59].allSatisfy { !$0 })
    }

    @Test func fluentSpeechWithoutLoudPeaksIsNotRejected() {
        // Same failure mode, worse outcome: fluent speech at an even
        // 0.005–0.012 with almost no silence pushed the old threshold above
        // every frame, so the gate rejected the entire recording.
        var energies = [Float](repeating: 0.0015, count: 4)
        energies += (0..<50).map { 0.005 + Float($0 % 4) * 0.002 }
        energies += [Float](repeating: 0.0015, count: 4)

        let activity = VoiceGate.voiceActivity(energies: energies)
        #expect(activity.count(where: { $0 }) == 50)
        let range = VoiceGate.activeFrameRange(
            voiceActivity: activity,
            paddingFrames: 3,
            minVoicedFrames: 2
        )
        #expect(range != nil)
    }

    // MARK: frameEnergies

    @Test func frameEnergiesComputesRMSPerFrame() {
        // 2 frames of 4 samples: constant 0.5 (RMS 0.5), then zeros (RMS 0).
        let samples: [Float] = [0.5, 0.5, 0.5, 0.5, 0, 0, 0, 0]
        let energies = VoiceGate.frameEnergies(samples: samples, frameSamples: 4)
        #expect(energies.count == 2)
        #expect(abs(energies[0] - 0.5) < 0.0001)
        #expect(abs(energies[1]) < 0.0001)
    }

    @Test func frameEnergiesHandlesPartialFinalFrame() {
        let samples = [Float](repeating: 0.5, count: 6)
        let energies = VoiceGate.frameEnergies(samples: samples, frameSamples: 4)
        #expect(energies.count == 2)
        #expect(abs(energies[1] - 0.5) < 0.0001)
    }

    // MARK: activeFrameRange

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

    @Test func trailingPaddingCanExceedLeadingPadding() {
        // The trim keeps extra audio after the last voiced frame: soft final
        // syllables sit near the threshold, and Whisper needs trailing
        // context to decode the last words.
        var frames = [Bool](repeating: false, count: 50)
        for i in 10...19 { frames[i] = true }
        let range = VoiceGate.activeFrameRange(
            voiceActivity: frames,
            paddingFrames: 3,
            trailingPaddingFrames: 10
        )
        #expect(range == 7..<30)
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
