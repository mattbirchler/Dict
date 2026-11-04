import AVFoundation
import Testing
@testable import Dict_app

struct TapConverterTests {
    private func buffer(sampleRate: Double, seconds: Double) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let frames = AVAudioFrameCount(sampleRate * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let channel = buffer.floatChannelData![0]
        for i in 0..<Int(frames) {
            channel[i] = 0.3 * Float(sin(2 * .pi * 440 * Double(i) / sampleRate))
        }
        return buffer
    }

    private var target: AVAudioFormat {
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    }

    /// AirPods switch from 48 kHz to 24 kHz once their mic opens. The
    /// converter follows the buffers' format, so both rates come out at
    /// 16 kHz with roughly the right number of frames. The first buffer
    /// after a rebuild runs a little short: the resampler holds back a few
    /// hundred frames of startup latency.
    @Test func followsSampleRateChange() {
        let converter = TapConverter(targetFormat: target)
        for rate in [48_000.0, 24_000.0, 48_000.0] {
            let out = converter.convert(buffer(sampleRate: rate, seconds: 0.1))
            #expect(out?.format.sampleRate == 16_000)
            let frames = Int(out?.frameLength ?? 0)
            #expect((1_200...1_700).contains(frames), "rate \(rate) gave \(frames) frames")
        }
    }
}
