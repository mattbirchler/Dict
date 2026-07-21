import Foundation
import Testing
@testable import Dict_app

@MainActor
struct ChunkDecodeQueueTests {
    private func request(_ text: String) -> ChunkDecodeQueue.Request {
        ChunkDecodeQueue.Request(samples: [0.1], promptText: text, threshold: 0.003)
    }

    @Test func returnsResultsInSubmissionOrder() async {
        let queue = ChunkDecodeQueue { req in
            // Invert the delay so a naive concurrent implementation would
            // return these out of order.
            let delay = req.promptText == "a" ? 200 : 10
            try? await Task.sleep(for: .milliseconds(delay))
            return req.promptText
        }
        queue.enqueue(request("a"))
        queue.enqueue(request("b"))
        let results = await queue.drain()
        #expect(results == ["a", "b"])
    }

    @Test func runsOneDecodeAtATime() async {
        let counter = Counter()
        let queue = ChunkDecodeQueue { _ in
            await counter.enter()
            try? await Task.sleep(for: .milliseconds(50))
            await counter.leave()
            return "x"
        }
        queue.enqueue(request("1"))
        queue.enqueue(request("2"))
        queue.enqueue(request("3"))
        _ = await queue.drain()
        #expect(await counter.maxConcurrent == 1)
    }

    @Test func recordsFailureAndDropsResult() async {
        let queue = ChunkDecodeQueue { req in
            req.promptText == "bad" ? nil : req.promptText
        }
        queue.enqueue(request("good"))
        queue.enqueue(request("bad"))
        let results = await queue.drain()
        #expect(results == ["good"])
        #expect(queue.hasFailed)
    }

    @Test func drainOnEmptyQueueReturnsNothing() async {
        let queue = ChunkDecodeQueue { _ in "unused" }
        #expect(await queue.drain().isEmpty)
        #expect(!queue.hasFailed)
    }

    /// Proves serialization directly: records the START/FINISH of every
    /// decode and asserts they are never interleaved, i.e. each decode's
    /// finish event immediately follows its own start event. A concurrent
    /// implementation would let decode 2 (short delay) finish while decode 1
    /// (long delay) is still running, which would show up here as
    /// start(1), start(2), finish(2), finish(1) instead of the required
    /// start(1), finish(1), start(2), finish(2), ...
    @Test func decodeStartAndFinishEventsNeverInterleave() async {
        let log = EventLog()
        let queue = ChunkDecodeQueue { req in
            let id = Int(req.promptText)!
            await log.record(.start(id))
            let delay = id == 1 ? 100 : 10
            try? await Task.sleep(for: .milliseconds(delay))
            await log.record(.finish(id))
            return req.promptText
        }
        queue.enqueue(request("1"))
        queue.enqueue(request("2"))
        queue.enqueue(request("3"))
        _ = await queue.drain()

        let events = await log.events
        #expect(events.count == 6)
        var index = 0
        while index < events.count {
            guard case .start(let id) = events[index] else {
                Issue.record("Expected a start event at position \(index), got \(events[index])")
                break
            }
            guard index + 1 < events.count, case .finish(let finishedId) = events[index + 1] else {
                Issue.record("Expected finish(\(id)) immediately after start(\(id))")
                break
            }
            #expect(finishedId == id)
            index += 2
        }
    }

    /// Proves Finding 1's fix: a decode already past its cancellation check
    /// is an uninterruptible Core ML call that keeps running after
    /// `cancelAll()`. A decode enqueued right after `cancelAll()` must still
    /// wait for that in-flight decode to actually finish rather than running
    /// alongside it.
    @Test func decodeAfterCancelAllDoesNotOverlapInFlightDecode() async {
        let counter = Counter()
        let gate = StartGate()
        let queue = ChunkDecodeQueue { req in
            await counter.enter()
            if req.promptText == "slow" {
                await gate.signalStarted()
                try? await Task.sleep(for: .milliseconds(150))
            } else {
                try? await Task.sleep(for: .milliseconds(10))
            }
            await counter.leave()
            return req.promptText
        }

        let slowHandle = queue.enqueue(request("slow"))
        // Wait until the slow decode is actually past its cancellation
        // guard and running the "uninterruptible" work, mirroring a real
        // cancel-then-restart during dictation.
        await gate.waitForStart()
        queue.cancelAll()
        let fastHandle = queue.enqueue(request("fast"))

        _ = await fastHandle.value
        _ = await slowHandle.value
        #expect(await counter.maxConcurrent == 1)
    }

    /// Proves the double-`cancelAll()` fix: the first `cancelAll()` folds
    /// the in-flight "slow" decode into a replacement chain; a second
    /// `cancelAll()` called before that chain resolves must fold the
    /// OUTGOING chain too, not just the (now empty) `handles` array. If it
    /// doesn't, the second chain resolves immediately from an empty list,
    /// orphaning the first chain, and a decode enqueued afterward starts
    /// while "slow" is still executing.
    @Test func doubleCancelAllStillWaitsForInFlightDecode() async {
        let counter = Counter()
        let gate = StartGate()
        let queue = ChunkDecodeQueue { req in
            await counter.enter()
            if req.promptText == "slow" {
                await gate.signalStarted()
                try? await Task.sleep(for: .milliseconds(150))
            } else {
                try? await Task.sleep(for: .milliseconds(10))
            }
            await counter.leave()
            return req.promptText
        }

        let slowHandle = queue.enqueue(request("slow"))
        // Wait until "slow" is genuinely past its cancellation guard and
        // running the uninterruptible work.
        await gate.waitForStart()
        queue.cancelAll()
        queue.cancelAll()
        let fastHandle = queue.enqueue(request("fast"))

        _ = await fastHandle.value
        _ = await slowHandle.value
        #expect(await counter.maxConcurrent == 1)
    }
}

/// Tracks peak concurrency to prove the queue serializes.
actor Counter {
    private var current = 0
    private(set) var maxConcurrent = 0
    func enter() { current += 1; maxConcurrent = max(maxConcurrent, current) }
    func leave() { current -= 1 }
}

/// Records decode START/FINISH events in wall-clock order so tests can
/// assert they never interleave.
actor EventLog {
    enum Event: Equatable {
        case start(Int)
        case finish(Int)
    }
    private(set) var events: [Event] = []
    func record(_ event: Event) { events.append(event) }
}

/// Lets a test await the moment a decode has actually started running
/// (past any cancellation guard), instead of guessing with a fixed delay.
actor StartGate {
    private var started = false
    private var continuation: CheckedContinuation<Void, Never>?

    func waitForStart() async {
        if started { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func signalStarted() {
        started = true
        continuation?.resume()
        continuation = nil
    }
}
