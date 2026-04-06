import Foundation

final class PipelineCoordinator {
    let audioRecorder = AudioRecorder()
    let whisperTranscriptionService = WhisperTranscriptionService()
    let textInsertionService = TextInsertionService()
    let historyStore = HistoryStore()

    private var segmentedCoordinator: SegmentedRecordingCoordinator?
    private var transcriptionQueue: TranscriptionQueue?

    func startRecording() {
        let queue = TranscriptionQueue(whisperService: whisperTranscriptionService)
        let coordinator = SegmentedRecordingCoordinator(
            audioRecorder: audioRecorder,
            transcriptionQueue: queue
        )

        self.transcriptionQueue = queue
        self.segmentedCoordinator = coordinator

        coordinator.start()
        print("[Pipeline] Recording session started")
    }

    func stopRecordingAndProcess() async -> String? {
        guard let coordinator = segmentedCoordinator, let queue = transcriptionQueue else {
            print("[Pipeline] No active session")
            return nil
        }

        coordinator.stop()
        self.segmentedCoordinator = nil

        print("[Pipeline] Waiting for transcription queue to complete...")
        let text = await queue.waitForCompletion()
        self.transcriptionQueue = nil

        print("[Pipeline] Assembled text: \"\(text)\"")
        guard !text.isEmpty else {
            print("[Pipeline] No text produced, aborting")
            return nil
        }

        historyStore.save(cleanedText: text)
        print("[Pipeline] Saved to history. Inserting text...")
        await textInsertionService.insertText(text)
        print("[Pipeline] Text inserted")

        return text
    }
}
