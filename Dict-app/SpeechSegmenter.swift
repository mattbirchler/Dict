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

        // Snapshot the threshold once per call rather than reading the
        // `sessionThreshold` computed property inside the loop: that
        // property sorts the entire session's `energies` every time, and
        // this loop can run once per timer tick (every 0.05s) for the
        // whole recording, so a per-frame sort makes append() cost grow
        // quadratically with session length. The snapshot is taken here,
        // before this call's frames are folded into `energies`, so it
        // reflects everything known through the previous call; this call's
        // own frames start influencing the threshold on the next call, a
        // lag of at most one timer tick, which is immaterial to a value
        // meant to track the session's noise floor over time.
        let threshold = sessionThreshold

        while pending.count - analyzed >= frameSamples {
            let frame = Array(pending[analyzed..<(analyzed + frameSamples)])
            analyzed += frameSamples
            let rms = VoiceGate.frameEnergies(samples: frame, frameSamples: frameSamples).first ?? 0
            energies.append(rms)
            if rms > threshold {
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
