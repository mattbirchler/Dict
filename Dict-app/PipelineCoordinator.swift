import Foundation

final class PipelineCoordinator {
    let audioRecorder = AudioRecorder()
    let transcriptionService = TranscriptionService()
    let aiCleanupService = AICleanupService()
    let textInsertionService = TextInsertionService()
    let historyStore = HistoryStore()

    private var currentAudioURL: URL?

    func startRecording() {
        do {
            currentAudioURL = try audioRecorder.startRecording()
        } catch {
            print("Failed to start recording: \(error)")
        }
    }

    func stopRecordingAndProcess() async -> String? {
        guard let audioURL = audioRecorder.stopRecording() else {
            return nil
        }

        do {
            let rawTranscript = try await transcriptionService.transcribe(audioURL: audioURL)
            guard !rawTranscript.isEmpty else { return nil }

            let cleanedText: String
            if aiCleanupService.isAvailable {
                cleanedText = try await aiCleanupService.cleanup(rawTranscript: rawTranscript)
            } else {
                cleanedText = rawTranscript
            }

            historyStore.save(cleanedText: cleanedText)
            await textInsertionService.insertText(cleanedText)

            return cleanedText
        } catch {
            print("Pipeline error: \(error)")
            try? FileManager.default.removeItem(at: audioURL)
            return nil
        }
    }
}
