import Foundation

@MainActor
final class PipelineCoordinator {
    let transcriptionService = StreamingTranscriptionService()
    let textInsertionService = TextInsertionService()
    let historyStore = HistoryStore()
    private let formatter = TranscriptFormatter()

    func startRecording() {
        Task {
            do {
                try await transcriptionService.start()
                print("[Pipeline] Streaming session started")
            } catch {
                print("[Pipeline] Failed to start streaming: \(error)")
            }
        }
    }

    func stopRecordingAndProcess() async -> String? {
        let rawText = await transcriptionService.stop()

        guard !rawText.isEmpty else {
            print("[Pipeline] No text produced, aborting")
            return nil
        }

        let text = await formatter.format(rawText)

        historyStore.save(cleanedText: text)
        print("[Pipeline] Saved to history. Inserting text...")
        await textInsertionService.insertText(text)
        print("[Pipeline] Text inserted")

        return text
    }
}
