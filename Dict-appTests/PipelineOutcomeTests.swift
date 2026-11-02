import Foundation
import Testing
@testable import Dict_app

struct PipelineOutcomeTests {
    struct EngineError: Error {}

    @Test func engineFailureIsFailedNotNothingHeard() {
        #expect(PipelineCoordinator.earlyResult(stop: .failure(EngineError()), startFailed: false) == .failed)
    }

    @Test func failedStartIsFailedEvenWithText() {
        #expect(PipelineCoordinator.earlyResult(stop: .success("hello"), startFailed: true) == .failed)
    }

    @Test func emptyTextIsNothingHeard() {
        #expect(PipelineCoordinator.earlyResult(stop: .success(""), startFailed: false) == .nothingHeard)
    }

    @Test func textProceedsToFormatting() {
        #expect(PipelineCoordinator.earlyResult(stop: .success("hello"), startFailed: false) == nil)
    }
}
