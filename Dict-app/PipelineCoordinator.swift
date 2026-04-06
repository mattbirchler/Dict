import Foundation

final class PipelineCoordinator {
    let audioRecorder = AudioRecorder()
    let whisperTranscriptionService = WhisperTranscriptionService()
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
            let text = try await whisperTranscriptionService.transcribe(audioURL: audioURL)
            print("[Pipeline] Transcript: \"\(text)\"")
            guard !text.isEmpty else {
                print("[Pipeline] Transcript is empty, aborting")
                return nil
            }

            historyStore.save(cleanedText: text)
            print("[Pipeline] Saved to history. Inserting text...")
            await textInsertionService.insertText(text)
            print("[Pipeline] Text inserted")

            return text
        } catch {
            print("[Pipeline] Error: \(error)")
            try? FileManager.default.removeItem(at: audioURL)
            return nil
        }
    }
}
