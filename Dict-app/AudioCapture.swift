import AVFoundation
import CoreAudio
import Foundation
import os

/// The microphone side of a recording: one AVAudioEngine, the tap on its
/// input node, and the restart when the input reconfigures mid-recording.
/// Both transcription engines record through one of these.
///
/// It's an actor so device selection and engine start run off the main
/// actor. A Bluetooth headset blocks those calls for a second or more
/// while it switches its mic on; on the main actor that froze the HUD.
///
/// The tap is always installed with the input node's *hardware* format,
/// read fresh, never with `format: nil` or the node's output format.
/// AVAudioEngine keeps the node's output format from the first device it
/// saw and does not refresh it; `reset()` and even a brand-new engine
/// report the same stale format. When the hardware's sample rate differs,
/// installTap raises an Objective-C exception that Swift can't catch, and
/// the unwinding corrupts the main actor so the next hotkey press crashes
/// the app. That mismatch happens whenever the mic changes between
/// recordings (AirPods to the built-in mic) and whenever AirPods drop from
/// 48 kHz to 24 kHz as their mic opens.
actor AudioCapture {
    typealias Tap = @Sendable (AVAudioPCMBuffer) -> Void

    private let engine = AVAudioEngine()
    private var tap: Tap?
    private var deviceID: AudioDeviceID?
    private var configurationObserver: (any NSObjectProtocol)?
    /// Restarts so far this capture. Capped so a device that keeps
    /// reconfiguring can't loop forever.
    private var restarts = 0
    private static let maxRestarts = 3
    /// True while a restart is waiting on the hardware, so the watchdog
    /// and a configuration-change notification don't start a second one.
    private var restarting = false
    /// Bumped by every start(). stop(generation:) only stops a capture
    /// that is still the one the caller started.
    private var generation = 0
    private(set) var isCapturing = false
    /// When the tap last delivered a buffer. The watchdog restarts the
    /// capture if that stops: a Bluetooth input can change its format
    /// under a running engine without any configuration-change
    /// notification, and the engine then just goes quiet.
    private let heartbeat = Heartbeat()
    private var watchdog: Task<Void, Never>?
    /// Buffers normally arrive every 85 ms (4096 frames at 48 kHz) to
    /// 170 ms (at 24 kHz), so this is several missed buffers.
    static let stallThreshold: Duration = .milliseconds(600)

    /// Starts recording from `deviceID` (nil leaves the system default)
    /// and feeds every buffer to `tap` on the realtime audio thread.
    /// Returns a generation token for stop(generation:).
    @discardableResult
    func start(deviceID: AudioDeviceID?, tap: @escaping Tap) async throws -> Int {
        if isCapturing { stop() }
        generation += 1
        let generation = generation
        let clock = ContinuousClock()
        let started = clock.now
        AudioInputDevices.applyIfPossible(deviceID, to: engine)
        self.deviceID = deviceID
        self.tap = tap
        restarts = 0
        do {
            try await installTapAndStart()
        } catch {
            if generation == self.generation { self.tap = nil }
            throw error
        }
        guard generation == self.generation, self.tap != nil else {
            // A stop() or newer start() came in while we waited on the
            // hardware; that one owns the engine now.
            if generation == self.generation {
                engine.inputNode.removeTap(onBus: 0)
                if engine.isRunning { engine.stop() }
            }
            throw CancellationError()
        }
        observeConfigurationChanges()
        isCapturing = true
        heartbeat.beat()
        startWatchdog()
        let format = engine.inputNode.inputFormat(forBus: 0)
        let elapsed = clock.now - started
        Log.engine.info("Capture started in \(elapsed, privacy: .public) on device \(deviceID.map(String.init) ?? "default", privacy: .public) at \(Self.describe(format), privacy: .public)")
        return generation
    }

    /// Stops the capture if it is still generation `generation` (or any,
    /// when nil). A start that was outpaced by the key release uses the
    /// token so it can't stop a newer recording.
    func stop(generation: Int? = nil) {
        if let generation, generation != self.generation { return }
        tap = nil
        isCapturing = false
        watchdog?.cancel()
        watchdog = nil
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
    }

    /// Taps with the hardware format and starts the engine.
    ///
    /// Starting is what makes AirPods open their mic, and that drops them
    /// from 48 kHz to 24 kHz. The start then fails with a format error
    /// and the input node keeps reporting the old rate for another
    /// ~200 ms, so an immediate retry fails the same way. On failure this
    /// waits for the node's format to actually change (up to
    /// `formatSettleTimeout`), then retries with the new one, a few times
    /// if the device keeps moving. Anything else leaves no tap behind and
    /// rethrows.
    private func installTapAndStart() async throws {
        var format = try hardwareFormat()
        var lastError: any Error
        do {
            try installTap(format: format)
            try startEngine()
            return
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            lastError = error
        }
        for _ in 0..<Self.maxStartRetries {
            guard let changed = try await waitForFormatChange(from: format) else { break }
            Log.engine.info("Input format changed while starting (\(Self.describe(format), privacy: .public) to \(Self.describe(changed), privacy: .public)), retrying")
            format = changed
            do {
                try installTap(format: format)
                try startEngine()
                return
            } catch {
                engine.inputNode.removeTap(onBus: 0)
                lastError = error
            }
        }
        throw lastError
    }

    private static let maxStartRetries = 3
    private static let formatSettleTimeout: Duration = .milliseconds(1500)

    /// Polls the input node until its format differs from `format`.
    /// Returns nil if it hasn't within `formatSettleTimeout`.
    private func waitForFormatChange(from format: AVAudioFormat) async throws -> AVAudioFormat? {
        let deadline = ContinuousClock.now + Self.formatSettleTimeout
        while ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
            let current = try hardwareFormat()
            if current != format { return current }
        }
        return nil
    }

    private func hardwareFormat() throws -> AVAudioFormat {
        let format = engine.inputNode.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AudioCaptureError.noInput
        }
        return format
    }

    /// Allocates the engine's resources ahead of the first recording. The
    /// first start of an engine otherwise reconfigures itself ~100 ms in,
    /// which costs a restart and the opening syllable. Doesn't open the
    /// mic, so the mic-in-use indicator stays off.
    func warmUp(deviceID: AudioDeviceID? = nil) {
        guard !isCapturing else { return }
        AudioInputDevices.applyIfPossible(deviceID, to: engine)
        _ = engine.inputNode
        engine.prepare()
    }

    private func installTap(format: AVAudioFormat) throws {
        // stop() clears the tap; if that happened while a start or
        // restart was waiting on the hardware, don't bring the engine up.
        guard let tap else { throw CancellationError() }
        let heartbeat = heartbeat
        let block: AVAudioNodeTapBlock = { buffer, _ in
            heartbeat.beat()
            tap(buffer)
        }
        if #available(macOS 27.0, *) {
            // The throwing variant turns a format mismatch into an error
            // instead of an uncatchable exception.
            try engine.inputNode.__installTap(onBus: 0, bufferSize: 4096, format: format, error: (), block: block)
        } else {
            engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: format, block: block)
        }
    }

    private func startEngine() throws {
        engine.prepare()
        try engine.start()
    }

    /// AVAudioEngine stops itself when the input device reconfigures,
    /// which AirPods do as they switch into call mode for the mic. Without
    /// a restart the rest of the recording would be silent.
    private func observeConfigurationChanges() {
        guard configurationObserver == nil else { return }
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            Task { await self?.restart(reason: "input reconfigured") }
        }
    }

    private func startWatchdog() {
        watchdog?.cancel()
        let generation = generation
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(150))
                guard let self, !Task.isCancelled else { return }
                await self.restartIfStalled(generation: generation)
            }
        }
    }

    private func restartIfStalled(generation: Int) async {
        guard isCapturing, self.generation == generation, !restarting else { return }
        let silence = heartbeat.age()
        guard silence > Self.stallThreshold else { return }
        await restart(reason: "no audio for \(silence)")
    }

    /// Tears the tap and engine down and brings them back on the current
    /// hardware format. Capped at `maxRestarts` per capture.
    private func restart(reason: String) async {
        guard isCapturing, tap != nil, restarts < Self.maxRestarts, !restarting else { return }
        restarts += 1
        restarting = true
        defer { restarting = false }
        let generation = generation
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        // Re-selecting the device makes the input node re-read the
        // hardware format; without this it can still report the old one.
        AudioInputDevices.applyIfPossible(deviceID, to: engine)
        do {
            try await installTapAndStart()
            guard generation == self.generation else { return }
            heartbeat.beat()
            Log.engine.info("Capture restarted (\(reason, privacy: .public)) at \(Self.describe(self.engine.inputNode.inputFormat(forBus: 0)), privacy: .public)")
        } catch {
            guard generation == self.generation, !(error is CancellationError) else { return }
            Log.engine.error("Couldn't restart capture (\(reason, privacy: .public)): \(String(describing: error), privacy: .public)")
            // The device may still be mid-transition; try again shortly.
            // Keep the heartbeat fresh so the watchdog waits its turn.
            heartbeat.beat()
            Task {
                try? await Task.sleep(for: .milliseconds(200))
                guard self.generation == generation else { return }
                await self.restart(reason: reason)
            }
        }
    }

    nonisolated static func describe(_ format: AVAudioFormat) -> String {
        "\(format.channelCount) ch \(Int(format.sampleRate)) Hz"
    }
}

/// A timestamp the realtime tap thread bumps and the actor reads.
nonisolated final class Heartbeat: Sendable {
    private let last = OSAllocatedUnfairLock(initialState: ContinuousClock.now)

    func beat() { last.withLock { $0 = .now } }

    func age() -> Duration { last.withLock { ContinuousClock.now - $0 } }
}

enum AudioCaptureError: LocalizedError {
    /// The input node reports no usable format: no microphone, or no
    /// microphone permission.
    case noInput

    var errorDescription: String? {
        switch self {
        case .noInput: "No microphone is available."
        }
    }
}
