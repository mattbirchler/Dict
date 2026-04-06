import Foundation

final class TranscriptionQueue {
    private let whisperService: WhisperTranscriptionService
    private var results: [Int: String] = [:]
    private var pendingSegments: [(index: Int, url: URL)] = []
    private var isProcessing = false
    private var continuation: CheckedContinuation<String, Never>?
    private var finalized = false
    private var nextSubmitIndex = 0

    init(whisperService: WhisperTranscriptionService) {
        self.whisperService = whisperService
    }

    func submit(segmentURL: URL) {
        let index = nextSubmitIndex
        nextSubmitIndex += 1
        pendingSegments.append((index: index, url: segmentURL))
        print("[TranscriptionQueue] Segment \(index) submitted: \(segmentURL.lastPathComponent)")
        processNext()
    }

    func waitForCompletion() async -> String {
        // If nothing is pending and nothing is processing, return immediately
        if pendingSegments.isEmpty && !isProcessing {
            return assembleText()
        }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.finalized = true
        }
    }

    private func processNext() {
        guard !isProcessing, !pendingSegments.isEmpty else { return }
        isProcessing = true

        let segment = pendingSegments.removeFirst()
        Task {
            do {
                let text = try await whisperService.transcribe(audioURL: segment.url)
                if !text.isEmpty {
                    results[segment.index] = text
                    print("[TranscriptionQueue] Segment \(segment.index) transcribed: \"\(text)\"")
                } else {
                    print("[TranscriptionQueue] Segment \(segment.index) produced empty text, skipping")
                }
            } catch {
                print("[TranscriptionQueue] Segment \(segment.index) failed: \(error)")
                // Clean up the file since WhisperTranscriptionService didn't get to it
                try? FileManager.default.removeItem(at: segment.url)
            }

            isProcessing = false

            if !pendingSegments.isEmpty {
                processNext()
            } else if finalized, let continuation {
                self.continuation = nil
                continuation.resume(returning: assembleText())
            }
        }
    }

    private func assembleText() -> String {
        let ordered = results.sorted { $0.key < $1.key }
        return ordered.map { $0.value }.joined(separator: " ")
    }
}
