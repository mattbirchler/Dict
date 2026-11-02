import Foundation
import Testing
@testable import Dict_app

struct DictationResultTests {
    @Test func hudMessages() {
        #expect(DictationResult.inserted("hi").hudMessage == nil)
        #expect(DictationResult.nothingHeard.hudMessage == "Nothing heard")
        #expect(DictationResult.failed.hudMessage == "Couldn't transcribe. Try again.")
    }

    @MainActor @Test func startIsBlockedWhileEnginePrepares() {
        let name = "DictationResultTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let state = AppState(settings: SettingsStore(defaults: defaults))
        state.isPreparingEngine = true
        #expect(state.canStartRecording == false)
        #expect(state.startBlockedReason == "Loading speech model…")
    }
}
