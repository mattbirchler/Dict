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

        pipeline.engineChoice = .parakeet
        #expect(pipeline.activeEngine === pipeline.parakeetEngine)
    }

    @Test func parakeetChoiceRoundTripsThroughDefaults() {
        let suiteName = "PipelineEngineSelectionTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        store.transcriptionEngine = .parakeet

        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.transcriptionEngine == .parakeet)
    }

    @Test func defaultChoiceIsApple() {
        let pipeline = PipelineCoordinator()
        #expect(pipeline.engineChoice == .apple)
        #expect(pipeline.activeEngine === pipeline.appleEngine)
    }
}
