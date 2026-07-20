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
}

/// Tracks peak concurrency to prove the queue serializes.
actor Counter {
    private var current = 0
    private(set) var maxConcurrent = 0
    func enter() { current += 1; maxConcurrent = max(maxConcurrent, current) }
    func leave() { current -= 1 }
}
