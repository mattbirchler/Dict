import Foundation
import Testing
@testable import Dict_app

struct SpectrumAnalyzerTests {
    private func sine(hz: Double, sampleRate: Double, seconds: Double, amplitude: Float = 0.3) -> [Float] {
        (0..<Int(sampleRate * seconds)).map { i in
            amplitude * Float(sin(2 * .pi * hz * Double(i) / sampleRate))
        }
    }

    /// The band holding the tone's frequency is the loudest; the band
    /// index grows with frequency because bands are low to high.
    @Test func toneLightsItsOwnBand() {
        let rate = 48_000.0
        let low = SpectrumAnalyzer.bands(samples: sine(hz: 200, sampleRate: rate, seconds: 0.1), sampleRate: rate)
        let high = SpectrumAnalyzer.bands(samples: sine(hz: 3_000, sampleRate: rate, seconds: 0.1), sampleRate: rate)
        #expect(low.count == SpectrumAnalyzer.bandCount)
        let lowPeak = low.indices.max { low[$0] < low[$1] }!
        let highPeak = high.indices.max { high[$0] < high[$1] }!
        #expect(lowPeak < highPeak)
        #expect(low[lowPeak] > 0.5)
        #expect(high[highPeak] > 0.5)
    }

    @Test func silenceIsDark() {
        let bands = SpectrumAnalyzer.bands(samples: [Float](repeating: 0, count: 4096), sampleRate: 48_000)
        #expect(bands.allSatisfy { $0 == 0 })
    }

    @Test func emptyInputGivesNoBands() {
        #expect(SpectrumAnalyzer.bands(samples: [], sampleRate: 48_000).isEmpty)
    }

    @Test func levelsStayInRange() {
        let loud = SpectrumAnalyzer.bands(samples: sine(hz: 1_000, sampleRate: 16_000, seconds: 0.2, amplitude: 1), sampleRate: 16_000)
        #expect(loud.allSatisfy { $0 >= 0 && $0 <= 1 })
        #expect(loud.max()! == 1)
    }
}

struct DotMatrixTests {
    @Test func peaksHoldThenDecayToLevel() {
        var levels = [Double](repeating: 0, count: DotMatrix.columns)
        var peaks = [Double](repeating: 0, count: DotMatrix.columns)
        var loud = [Float](repeating: 0, count: DotMatrix.columns)
        loud[3] = 1
        DotMatrix.step(levels: &levels, peaks: &peaks, incoming: loud)
        #expect(levels[3] > 0.7)
        #expect(peaks[3] == levels[3])

        let quiet = [Float](repeating: 0, count: DotMatrix.columns)
        DotMatrix.step(levels: &levels, peaks: &peaks, incoming: quiet)
        #expect(levels[3] < peaks[3], "release is slower than the peak")
        let before = peaks[3]
        DotMatrix.decayPeaks(&peaks, floor: levels)
        #expect(peaks[3] < before)
        #expect(peaks[3] >= levels[3])
    }

    @Test func shortSpectrumIsPaddedWithSilence() {
        var levels = [Double](repeating: 0.5, count: DotMatrix.columns)
        var peaks = [Double](repeating: 0, count: DotMatrix.columns)
        DotMatrix.step(levels: &levels, peaks: &peaks, incoming: [1, 1])
        #expect(levels[DotMatrix.columns - 1] < 0.5)
    }
}
