import Foundation

/// Serializes chunk decodes onto the single shared WhisperKit pipeline.
///
/// Only one decode runs at a time: the Neural Engine is the bottleneck and
/// overlapping decodes on one pipeline is not supported. Because a Core ML
/// decode in flight cannot be cheaply interrupted, the worst case for the
/// final tail decode is waiting behind exactly one chunk, which is why
/// SpeechSegmenter caps chunk length.
@MainActor
final class ChunkDecodeQueue {
    struct Request: Sendable {
        let samples: [Float]
        let promptText: String
        let threshold: Float
    }

    private let decode: @Sendable (Request) async -> String?
    private var chain: Task<Void, Never> = Task {}
    private var handles: [Task<String?, Never>] = []
    private(set) var hasFailed = false

    init(decode: @escaping @Sendable (Request) async -> String?) {
        self.decode = decode
    }

    @discardableResult
    func enqueue(_ request: Request) -> Task<String?, Never> {
        let previous = chain
        let decode = self.decode
        let handle = Task { @MainActor [weak self] () -> String? in
            // Wait for the previous decode so only one runs at a time.
            _ = await previous.value
            guard !Task.isCancelled else { return nil }
            let text = await decode(request)
            if text == nil { self?.hasFailed = true }
            return text
        }
        handles.append(handle)
        chain = Task { _ = await handle.value }
        return handle
    }

    /// Awaits every enqueued decode and returns the successful results in
    /// submission order.
    func drain() async -> [String] {
        var results: [String] = []
        for handle in handles {
            if let text = await handle.value, !text.isEmpty {
                results.append(text)
            }
        }
        handles = []
        return results
    }

    func cancelAll() {
        for handle in handles { handle.cancel() }
        handles = []
        chain = Task {}
    }
}
