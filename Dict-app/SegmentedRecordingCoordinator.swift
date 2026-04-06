import Foundation

final class SegmentedRecordingCoordinator {
    enum State {
        case recording
        case stopped
    }

    private let audioRecorder: AudioRecorder
    private let transcriptionQueue: TranscriptionQueue
    private(set) var state: State = .stopped

    private var silenceTimer: Timer?
    private var levelCheckTimer: Timer?

    private static let silenceDuration: TimeInterval = 1.5
    private static let silenceThreshold: Float = 0.02
    private static let checkInterval: TimeInterval = 0.05

    init(audioRecorder: AudioRecorder, transcriptionQueue: TranscriptionQueue) {
        self.audioRecorder = audioRecorder
        self.transcriptionQueue = transcriptionQueue
    }

    func start() {
        guard state == .stopped else { return }
        startNewSegment()
    }

    func stop() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        levelCheckTimer?.invalidate()
        levelCheckTimer = nil

        if state == .recording {
            finalizeCurrentSegment()
        }

        state = .stopped
    }

    // MARK: - Segment management

    private func startNewSegment() {
        do {
            _ = try audioRecorder.startRecording()
            state = .recording
            print("[SegmentedRecording] Started new segment")
            startSilenceDetection()
        } catch {
            print("[SegmentedRecording] Failed to start recording: \(error)")
            state = .stopped
        }
    }

    private func finalizeCurrentSegment() {
        guard let url = audioRecorder.stopRecording() else {
            print("[SegmentedRecording] stopRecording returned nil")
            return
        }
        print("[SegmentedRecording] Finalized segment: \(url.lastPathComponent)")
        transcriptionQueue.submit(segmentURL: url)
    }

    // MARK: - Silence detection

    private func startSilenceDetection() {
        silenceTimer?.invalidate()
        silenceTimer = nil

        levelCheckTimer?.invalidate()
        levelCheckTimer = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            guard let self, self.state == .recording else { return }

            if self.audioRecorder.currentLevel < Self.silenceThreshold {
                // Below threshold — start or continue silence timer
                if self.silenceTimer == nil {
                    self.silenceTimer = Timer.scheduledTimer(withTimeInterval: Self.silenceDuration, repeats: false) { [weak self] _ in
                        guard let self, self.state == .recording else { return }
                        self.onSilenceDetected()
                    }
                }
            } else {
                // Above threshold — reset silence timer
                self.silenceTimer?.invalidate()
                self.silenceTimer = nil
            }
        }
    }

    private func onSilenceDetected() {
        print("[SegmentedRecording] Silence detected, splitting segment")
        levelCheckTimer?.invalidate()
        levelCheckTimer = nil
        silenceTimer?.invalidate()
        silenceTimer = nil

        finalizeCurrentSegment()
        startNewSegment()
    }
}
