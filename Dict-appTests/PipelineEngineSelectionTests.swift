import Foundation
import Testing
@testable import Dict_app

@MainActor
struct PipelineEngineSelectionTests {
    @Test func activeEngineFollowsChoice() {
        let pipeline = PipelineCoordinator()

        pipeline.engineChoice = .apple
        #expect(pipeline.activeEngine === pipeline.appleEngine)

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

    @Test func parakeetSkipsFormattingOutsideCodingApps() {
        #expect(!PipelineCoordinator.shouldFormat(enabled: true, engine: .parakeet, context: .general))
        #expect(PipelineCoordinator.shouldFormat(enabled: true, engine: .parakeet, context: .coding))
        #expect(PipelineCoordinator.shouldFormat(enabled: true, engine: .apple, context: .general))
        #expect(PipelineCoordinator.shouldFormat(enabled: true, engine: .apple, context: .coding))
        #expect(!PipelineCoordinator.shouldFormat(enabled: false, engine: .apple, context: .coding))
        #expect(!PipelineCoordinator.shouldFormat(enabled: false, engine: .parakeet, context: .coding))
    }

    @Test func cleanAndPolishedAlwaysUseTheModel() {
        #expect(PipelineCoordinator.shouldFormat(enabled: true, engine: .parakeet, context: .general, style: .clean))
        #expect(PipelineCoordinator.shouldFormat(enabled: true, engine: .parakeet, context: .general, style: .polished))
        #expect(!PipelineCoordinator.shouldFormat(enabled: true, engine: .parakeet, context: .general, style: .verbatim))
        #expect(!PipelineCoordinator.shouldFormat(enabled: false, engine: .apple, context: .general, style: .clean))
    }

    @Test func verbatimTidiesHandsFreeDictations() {
        #expect(PipelineCoordinator.effectiveStyle(selected: .verbatim, handsFree: true, context: .general) == .tidy)
        #expect(PipelineCoordinator.effectiveStyle(selected: .verbatim, handsFree: false, context: .general) == .verbatim)
        // Coding apps keep Verbatim's technical-term pass.
        #expect(PipelineCoordinator.effectiveStyle(selected: .verbatim, handsFree: true, context: .coding) == .verbatim)
        // Other styles are left as chosen.
        #expect(PipelineCoordinator.effectiveStyle(selected: .clean, handsFree: true, context: .general) == .clean)
        #expect(PipelineCoordinator.effectiveStyle(selected: .polished, handsFree: true, context: .general) == .polished)
        #expect(PipelineCoordinator.shouldFormat(enabled: true, engine: .parakeet, context: .general, style: .tidy))
    }

    @Test func parakeetPadsBothEdgesWithSilence() {
        let samples: [Float] = [0.5, -0.5]
        let padded = ParakeetTranscriptionService.padded(samples, seconds: 0.25, sampleRate: 16)
        #expect(padded == [0, 0, 0, 0, 0.5, -0.5, 0, 0, 0, 0])
    }
}
