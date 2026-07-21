import Accelerate
import Foundation

/// Pure logic for gating and trimming a recording based on per-frame
/// audio energy.
///
/// The voiced/unvoiced decision uses a threshold adaptive to each
/// recording's own noise floor rather than a fixed absolute value: real
/// mic levels vary wildly with hardware and input gain (speech on this
/// machine peaks around 0.010 RMS while WhisperKit's fixed default was
/// 0.022 — above speech, so everything read as silence).
enum VoiceGate {
    /// Never treat frames below this RMS as voice, however low the floor —
    /// keeps near-digital-silence rooms from amplifying tiny wobbles.
    static let absoluteFloor: Float = 0.003
    /// A frame counts as voice when it exceeds this multiple of the
    /// recording's noise floor (10th-percentile frame energy).
    static let floorMultiplier: Float = 3.0
    /// The threshold is additionally capped at this fraction of the
    /// 90th-percentile energy: in push-to-talk recordings the user speaks
    /// most of the time, so low percentiles can land on speech instead of
    /// silence and push the floor-derived threshold above real words. The
    /// cap guarantees frames near speech level always count as voice.
    /// Misclassifying quiet frames as voice only costs Whisper a little
    /// extra audio; misclassifying speech as silence loses words.
    static let loudFraction: Float = 0.5

    /// RMS energy per frame (the quantity WhisperKit's VAD thresholds).
    /// The final frame may be shorter than `frameSamples`.
    static func frameEnergies(samples: [Float], frameSamples: Int) -> [Float] {
        guard frameSamples > 0, !samples.isEmpty else { return [] }
        var energies: [Float] = []
        energies.reserveCapacity(samples.count / frameSamples + 1)
        var start = 0
        while start < samples.count {
            let end = min(start + frameSamples, samples.count)
            var rms: Float = 0
            samples[start..<end].withUnsafeBufferPointer { buf in
                vDSP_rmsqv(buf.baseAddress!, 1, &rms, vDSP_Length(buf.count))
            }
            energies.append(rms)
            start = end
        }
        return energies
    }

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

    /// The frame range spanning first-to-last voice activity, padded on
    /// both sides and clamped to the buffer. Nil when fewer than
    /// `minVoicedFrames` frames have voice — the caller should skip
    /// transcription entirely. Requiring 2+ frames keeps a single click or
    /// cough in an otherwise silent recording from opening the gate.
    /// `trailingPaddingFrames` (defaults to `paddingFrames`) can be larger:
    /// trailing speech tends to be softer and Whisper needs context after
    /// the final word, so under-trimming the tail is the safe direction.
    static func activeFrameRange(
        voiceActivity: [Bool],
        paddingFrames: Int,
        trailingPaddingFrames: Int? = nil,
        minVoicedFrames: Int = 1
    ) -> Range<Int>? {
        guard voiceActivity.count(where: { $0 }) >= max(1, minVoicedFrames),
              let first = voiceActivity.firstIndex(of: true),
              let last = voiceActivity.lastIndex(of: true) else {
            return nil
        }
        let start = max(0, first - paddingFrames)
        let end = min(voiceActivity.count, last + 1 + (trailingPaddingFrames ?? paddingFrames))
        return start..<end
    }
}
