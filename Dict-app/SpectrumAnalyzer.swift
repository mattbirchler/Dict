import Accelerate
import AVFoundation
import Foundation

/// Turns a buffer of microphone audio into a handful of band levels for the
/// HUD's dot matrix: one column per band, low frequencies on the left.
/// Pure and nonisolated so the realtime tap thread can call it directly.
enum SpectrumAnalyzer {
    /// Columns in the HUD matrix.
    static let bandCount = 20
    /// Speech lives here; nothing above is worth a column.
    static let lowHz: Double = 90
    static let highHz: Double = 7_000
    private static let fftSize = 2048
    private static let log2n = vDSP_Length(11)

    /// Band amplitudes for the first channel of `buffer`; feed them to a
    /// `SpectrumGain` for display levels.
    nonisolated static func bandAmplitudes(_ buffer: AVAudioPCMBuffer, count: Int = bandCount) -> [Float] {
        guard let channel = buffer.floatChannelData?[0] else { return [] }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return [] }
        let samples = Array(UnsafeBufferPointer(start: channel, count: frames))
        return bandAmplitudes(samples: samples, sampleRate: buffer.format.sampleRate, count: count)
    }

    /// Band levels (0...1) on a fixed dB window, for tests and callers
    /// without a `SpectrumGain`.
    nonisolated static func bands(samples: [Float], sampleRate: Double, count: Int = bandCount) -> [Float] {
        bandAmplitudes(samples: samples, sampleRate: sampleRate, count: count).map(normalized(amplitude:))
    }

    /// Mean linear amplitude per band, scaled so a full-scale sine reads
    /// about 1.0 in its own band and silence reads 0.
    nonisolated static func bandAmplitudes(samples: [Float], sampleRate: Double, count: Int = bandCount) -> [Float] {
        guard count > 0, sampleRate > 0, !samples.isEmpty else { return [] }
        let n = fftSize
        var input = [Float](repeating: 0, count: n)
        let tail = samples.suffix(n)
        input.replaceSubrange(0..<tail.count, with: tail)

        var window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_DENORM))
        vDSP_vmul(input, 1, window, 1, &input, 1, vDSP_Length(n))

        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return [] }
        defer { vDSP_destroy_fftsetup(setup) }

        let half = n / 2
        var real = [Float](repeating: 0, count: half)
        var imag = [Float](repeating: 0, count: half)
        var magnitudes = [Float](repeating: 0, count: half)
        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                input.withUnsafeBufferPointer { inPtr in
                    inPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                // zrip packs the real FFT with a factor of 2; |X| / N then
                // puts a full-scale sine at about 1.0 in its bin.
                vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(half))
            }
        }
        var scale = Float(1) / Float(n)
        vDSP_vsmul(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(half))

        // Bin k holds frequency k * sampleRate / n.
        let hzPerBin = sampleRate / Double(n)
        var out = [Float](repeating: 0, count: count)
        let ratio = highHz / lowHz
        for band in 0..<count {
            let from = lowHz * pow(ratio, Double(band) / Double(count))
            let to = lowHz * pow(ratio, Double(band + 1) / Double(count))
            let first = max(1, Int(from / hzPerBin))
            let last = max(first, min(half - 1, Int(to / hzPerBin)))
            // The loudest bin in the band, so a tone lights its band fully
            // whatever the band's width.
            out[band] = magnitudes[first...last].max() ?? 0
        }
        return out
    }

    /// Maps a band amplitude to 0...1 on a dB scale: `floorDB` and below
    /// is dark, `ceilingDB` and above is fully lit. Speech from a
    /// microphone sits around -45 to -20 dBFS per band.
    static let floorDB: Float = -58
    static let ceilingDB: Float = -22

    nonisolated static func normalized(amplitude: Float) -> Float {
        guard amplitude > 0 else { return 0 }
        let db = 20 * log10(max(amplitude, 1e-7))
        return min(max((db - floorDB) / (ceilingDB - floorDB), 0), 1)
    }
}

/// Adapts the matrix to the microphone: the loudest band sets a reference
/// that decays slowly, and everything is lit relative to it, so a hot
/// podcast mic and a quiet laptop mic both show the shape of the voice
/// instead of a solid block. One per recording.
struct SpectrumGain {
    /// Decibels from dark to fully lit below the reference.
    static let range: Float = 30
    /// The reference never drops below this, so a silent room isn't
    /// boosted into a lit grid.
    static let minimumReference: Float = -48
    /// Anything quieter is unconditionally dark.
    static let noiseFloor: Float = -74
    /// How fast the reference falls between louder moments, per update
    /// (updates arrive about every 85 ms, so roughly 7 dB a second).
    static let releasePerUpdate: Float = 0.6

    private(set) var reference: Float = SpectrumGain.minimumReference

    /// Levels (0...1) for one update of band amplitudes.
    mutating func levels(amplitudes: [Float]) -> [Float] {
        guard !amplitudes.isEmpty else { return [] }
        let decibels = amplitudes.map { 20 * log10(max($0, 1e-7)) }
        let loudest = decibels.max() ?? Self.noiseFloor
        if loudest > reference {
            reference = loudest
        } else {
            reference = max(Self.minimumReference, reference - Self.releasePerUpdate)
        }
        let floor = reference - Self.range
        return decibels.map { db in
            guard db > Self.noiseFloor else { return 0 }
            return min(max((db - floor) / Self.range, 0), 1)
        }
    }
}
