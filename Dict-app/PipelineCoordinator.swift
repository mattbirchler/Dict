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
            print("[Pipeline] Recording started. Temp file: \(currentAudioURL?.path ?? "nil")")
        } catch {
            print("[Pipeline] Failed to start recording: \(error)")
        }
    }

    func stopRecordingAndProcess() async -> String? {
        guard let audioURL = audioRecorder.stopRecording() else {
            print("[Pipeline] stopRecording returned nil URL")
            return nil
        }
        print("[Pipeline] Recording stopped. Audio file: \(audioURL.path)")

        do {
            print("[Pipeline] Starting transcription...")
            let rawTranscript = try await transcriptionService.transcribe(audioURL: audioURL)
            print("[Pipeline] Raw transcript: \"\(rawTranscript)\"")
            guard !rawTranscript.isEmpty else {
                print("[Pipeline] Transcript is empty, aborting")
                return nil
            }

            let cleanedText: String
            print("[Pipeline] AI cleanup available: \(aiCleanupService.isAvailable)")
            if aiCleanupService.isAvailable {
                print("[Pipeline] Running AI cleanup...")
                cleanedText = try await aiCleanupService.cleanup(rawTranscript: rawTranscript)
                print("[Pipeline] Cleaned text: \"\(cleanedText)\"")
            } else {
                print("[Pipeline] AI cleanup not available, using raw transcript")
                cleanedText = rawTranscript
            }

            historyStore.save(cleanedText: cleanedText)
            print("[Pipeline] Saved to history. Inserting text...")
            await textInsertionService.insertText(cleanedText)
            print("[Pipeline] Text inserted")

            return cleanedText
        } catch {
            print("[Pipeline] Error: \(error)")
            try? FileManager.default.removeItem(at: audioURL)
            return nil
        }
    }
}
