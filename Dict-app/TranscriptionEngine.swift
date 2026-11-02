import CoreAudio
import Foundation

/// A pluggable on-device transcription engine. Parakeet (FluidAudio) and
/// Apple's SpeechAnalyzer sit behind this so the pipeline can switch between them.
/// Class-bound (`AnyObject`) so the pipeline holds a shared reference.
@MainActor
protocol TranscriptionEngine: AnyObject {
    /// Trailing rolling buffer of recent audio levels; the HUD reads `.last`
    /// (normalized ~0...1) to drive the waveform.
    var audioEnergy: [Float] { get }

    var isRecording: Bool { get }

    /// The microphone to record from next; nil leaves the engine's default.
    /// Set by the pipeline right before start().
    var inputDeviceID: AudioDeviceID? { get set }

    /// True once the engine's model/assets are installed and loaded so
    /// recording can begin immediately.
    var isReady: Bool { get }

    /// True when this engine has a user-visible download step before it is
    /// usable (Parakeet). Apple reports false unless a first-time asset install
    /// is genuinely in progress.
    var needsDownload: Bool { get }

    /// Download/prepare progress callback (0...1), invoked during `prepare()`.
    var onProgress: ((Double) -> Void)? { get set }

    /// Idempotent: download/install and load whatever the engine needs.
    func prepare() async throws

    func start() async throws
    func cancel()
    /// Ends the recording and returns the transcript; throws when the
    /// engine failed, so the pipeline can tell failure from silence.
    func stop() async throws -> String

    /// Whether the engine can preview its transcript while recording.
    var supportsLiveTranscript: Bool { get }

    /// What has been heard so far in the current recording; empty when the
    /// engine doesn't preview or nothing has been decoded yet.
    var liveTranscript: LiveTranscript { get }

    /// Called when the user goes hands-free, where the preview is shown.
    /// Engines whose preview costs extra work start it here.
    func beginLivePreview()
}

/// Engines without a preview get an empty one.
extension TranscriptionEngine {
    var supportsLiveTranscript: Bool { false }
    var liveTranscript: LiveTranscript { LiveTranscript() }
    func beginLivePreview() {}
}
