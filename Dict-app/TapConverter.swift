import AVFoundation

/// Converts mic tap buffers to a fixed target format, building its
/// AVAudioConverter from whatever format the buffers actually arrive in.
///
/// Taps are installed with `format: nil` because AVAudioEngine raises an
/// Objective-C exception (which Swift can't catch) when an explicit tap
/// format disagrees with the hardware. That happens with AirPods: selecting
/// them as the mic drops them into a 24 kHz call mode after the engine has
/// already cached a 48 kHz format. Reading the format off each buffer keeps
/// the conversion right even if the device changes mid-recording.
///
/// Only touched from the tap callback, which AVAudioEngine calls serially
/// on its own thread, so the mutable state needs no lock.
nonisolated final class TapConverter: @unchecked Sendable {
    let targetFormat: AVAudioFormat
    private var converter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?

    init(targetFormat: AVAudioFormat) {
        self.targetFormat = targetFormat
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if sourceFormat != buffer.format {
            sourceFormat = buffer.format
            converter = AVAudioConverter(from: buffer.format, to: targetFormat)
        }
        guard let converter else { return nil }
        return Self.convert(buffer, using: converter, to: targetFormat)
    }

    /// Sample-rate-aware conversion of one buffer.
    static func convert(_ buffer: AVAudioPCMBuffer,
                        using converter: AVAudioConverter,
                        to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var supplied = false
        var err: NSError?
        converter.convert(to: out, error: &err) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        return err == nil ? out : nil
    }
}
