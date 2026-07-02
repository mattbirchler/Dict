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
    /// recording's noise floor (25th-percentile frame energy).
    static let floorMultiplier: Float = 3.0

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

    /// Voiced flags via an adaptive threshold:
    /// `max(absoluteFloor, floorMultiplier × 25th-percentile energy)`.
    static func voiceActivity(energies: [Float]) -> [Bool] {
        guard !energies.isEmpty else { return [] }
        let sorted = energies.sorted()
        let noiseFloor = sorted[min(sorted.count - 1, sorted.count / 4)]
        let threshold = max(absoluteFloor, noiseFloor * floorMultiplier)
        return energies.map { $0 > threshold }
    }

    /// The frame range spanning first-to-last voice activity, padded on
    /// both sides and clamped to the buffer. Nil when fewer than
    /// `minVoicedFrames` frames have voice — the caller should skip
    /// transcription entirely. Requiring 2+ frames keeps a single click or
    /// cough in an otherwise silent recording from opening the gate.
    static func activeFrameRange(
        voiceActivity: [Bool],
        paddingFrames: Int,
        minVoicedFrames: Int = 1
    ) -> Range<Int>? {
        guard voiceActivity.count(where: { $0 }) >= max(1, minVoicedFrames),
              let first = voiceActivity.firstIndex(of: true),
              let last = voiceActivity.lastIndex(of: true) else {
            return nil
        }
        let start = max(0, first - paddingFrames)
        let end = min(voiceActivity.count, last + 1 + paddingFrames)
        return start..<end
    }
}
