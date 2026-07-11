import Foundation
import Testing
@testable import Dict_app

@MainActor
struct PipelineEngineSelectionTests {
    @Test func activeEngineFollowsChoice() {
        let pipeline = PipelineCoordinator()

        pipeline.engineChoice = .apple
        #expect(pipeline.activeEngine === pipeline.appleEngine)

        pipeline.engineChoice = .whisper
        #expect(pipeline.activeEngine === pipeline.whisperEngine)
    }

    @Test func defaultChoiceIsApple() {
        let pipeline = PipelineCoordinator()
        #expect(pipeline.engineChoice == .apple)
        #expect(pipeline.activeEngine === pipeline.appleEngine)
    }
}
