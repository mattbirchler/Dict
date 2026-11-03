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

    /// Band levels (0...1) for the first channel of `buffer`.
    nonisolated static func bands(_ buffer: AVAudioPCMBuffer, count: Int = bandCount) -> [Float] {
        guard let channel = buffer.floatChannelData?[0] else { return [] }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return [] }
        let samples = Array(UnsafeBufferPointer(start: channel, count: frames))
        return bands(samples: samples, sampleRate: buffer.format.sampleRate, count: count)
    }

    /// Band levels (0...1) for raw mono samples. Uses the last `fftSize`
    /// samples (zero-padded when fewer), a Hann window, and log-spaced
    /// bands between `lowHz` and `highHz`.
    nonisolated static func bands(samples: [Float], sampleRate: Double, count: Int = bandCount) -> [Float] {
        guard count > 0, sampleRate > 0, !samples.isEmpty else { return [] }
        let n = fftSize
        var input = [Float](repeating: 0, count: n)
        let tail = samples.suffix(n)
        input.replaceSubrange(0..<tail.count, with: tail)

        var window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
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
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(half))
            }
        }

        // Bin k holds frequency k * sampleRate / n.
        let hzPerBin = sampleRate / Double(n)
        var out = [Float](repeating: 0, count: count)
        let ratio = highHz / lowHz
        for band in 0..<count {
            let from = lowHz * pow(ratio, Double(band) / Double(count))
            let to = lowHz * pow(ratio, Double(band + 1) / Double(count))
            let first = max(1, Int(from / hzPerBin))
            let last = max(first, min(half - 1, Int(to / hzPerBin)))
            var sum: Float = 0
            for bin in first...last { sum += magnitudes[bin] }
            let mean = sum / Float(last - first + 1)
            out[band] = normalized(power: mean)
        }
        return out
    }

    /// Maps mean band power to 0...1 on a compressed scale so quiet speech
    /// lights the lower dots and shouting clips at the top.
    nonisolated static func normalized(power: Float) -> Float {
        guard power > 0 else { return 0 }
        let amplitude = power.squareRoot()
        // Speech bands sit around 1e-3...3e-1 after the normalized window.
        let db = 20 * log10(max(amplitude, 1e-6))
        let floor: Float = -62, ceiling: Float = -12
        return min(max((db - floor) / (ceiling - floor), 0), 1)
    }
}
