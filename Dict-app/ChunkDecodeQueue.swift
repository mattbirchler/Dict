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
    // Cleared by every `drain()` or `cancelAll()`, which are the only two
    // ways a caller ever finishes with this queue: it is created fresh per
    // recording session and one of those two is always called at the end of
    // that session, so entries never accumulate beyond one session's worth
    // of chunks. Each entry is just a `Task<String?, Never>` handle; the
    // `Request` (including its `[Float]` sample buffer) is captured only by
    // the task's operation closure, which releases it once the closure body
    // returns, well before `drain()`/`cancelAll()` clears the array.
    private var handles: [Task<String?, Never>] = []
    private(set) var hasFailed = false

    init(decode: @escaping @Sendable (Request) async -> String?) {
        self.decode = decode
    }

    /// Seeds this queue's serialization chain from a predecessor queue's
    /// current chain tail, so the first decode enqueued here still waits
    /// for whatever that predecessor had in flight. Needed because a
    /// caller may replace the queue (e.g. cancel() followed by a fast
    /// restart) while an uninterruptible Core ML decode from the outgoing
    /// queue is still running on the shared WhisperKit pipeline — without
    /// this, the new queue's chain starts empty and a decode enqueued on
    /// it could run concurrently with that orphaned decode. Awaiting
    /// `previous` happens inside a detached `Task`, so construction itself
    /// never blocks on the predecessor.
    init(after previous: ChunkDecodeQueue?, decode: @escaping @Sendable (Request) async -> String?) {
        self.decode = decode
        if let previous {
            let tail = previous.chainTail()
            chain = Task { _ = await tail.value }
        }
    }

    /// The current tail of the serialization chain: resolves once every
    /// decode enqueued so far (including any in-flight decode folded in by
    /// `cancelAll()`) has actually finished. Exposed so a replacement queue
    /// can seed its own chain from it (see `init(after:decode:)`).
    func chainTail() -> Task<Void, Never> {
        chain
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
        // A decode already past its cancellation check is running an
        // uninterruptible Core ML inference and will keep running until it
        // returns. Fold the cancelled handles into the replacement chain so
        // any decode enqueued after this call still waits for that in-flight
        // decode to actually finish, preserving the one-decode-at-a-time
        // guarantee across the cancel boundary.
        //
        // Also fold in the OUTGOING `chain`, not just `handles`. A prior
        // `cancelAll()` may already have folded an in-flight decode into
        // `chain` while `handles` was cleared to []; if this call only
        // considered `handles`, it would rebuild `chain` from an empty list
        // that resolves immediately, silently orphaning that earlier fold
        // and letting a subsequently enqueued decode start while the
        // original in-flight decode is still running. Awaiting the prior
        // chain here is safe from deadlock: `chain` is always replaced with
        // a brand new `Task` before capture, so `priorChain` is always a
        // distinct, already-in-flight (or already-resolved) task, never
        // this new task itself.
        let priorChain = chain
        let cancelled = handles
        handles = []
        chain = Task {
            _ = await priorChain.value
            for handle in cancelled {
                _ = await handle.value
            }
        }
    }
}
