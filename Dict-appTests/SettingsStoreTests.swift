import Foundation
import Testing
@testable import Dict_app

@MainActor
struct SettingsStoreTests {
    /// Isolated UserDefaults per test so tests can't pollute each other or
    /// the real app preferences.
    private func makeDefaults() -> UserDefaults {
        let name = "SettingsStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func defaultsWhenNothingStored() {
        let store = SettingsStore(defaults: makeDefaults())
        #expect(store.hotkey == .rightCommand)
        #expect(store.activationMode == .holdToTalk)
        #expect(store.isFormattingEnabled == true)
        #expect(store.historyLimit == .fifty)
    }

    @Test func persistsAndReloads() {
        let defaults = makeDefaults()
        let store = SettingsStore(defaults: defaults)
        store.hotkey = .fn
        store.activationMode = .toggle
        store.isFormattingEnabled = false
        store.historyLimit = .unlimited

        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.hotkey == .fn)
        #expect(reloaded.activationMode == .toggle)
        #expect(reloaded.isFormattingEnabled == false)
        #expect(reloaded.historyLimit == .unlimited)
    }

    @Test func migratesExistingFormattingKey() {
        // Users of the current build already have this exact key.
        let defaults = makeDefaults()
        defaults.set(false, forKey: "isFormattingEnabled")
        let store = SettingsStore(defaults: defaults)
        #expect(store.isFormattingEnabled == false)
    }

    @Test func ignoresCorruptStoredValues() {
        let defaults = makeDefaults()
        defaults.set("not-a-real-hotkey", forKey: "hotkey")
        defaults.set("nope", forKey: "historyLimit")
        let store = SettingsStore(defaults: defaults)
        #expect(store.hotkey == .rightCommand)
        #expect(store.historyLimit == .fifty)
    }

    @Test func firesOnChangeForEachProperty() {
        let store = SettingsStore(defaults: makeDefaults())
        var changes: [SettingsStore.Change] = []
        store.onChange = { changes.append($0) }
        store.hotkey = .rightOption
        store.activationMode = .toggle
        store.isFormattingEnabled = false
        store.historyLimit = .ten
        #expect(changes == [.hotkey, .activationMode, .formatting, .historyLimit])
    }

    @Test func defaultEngineIsAppleOnFreshInstall() {
        let store = SettingsStore(defaults: makeDefaults())
        #expect(store.transcriptionEngine == .apple)
    }

    @Test func existingUserMigratesToWhisper() {
        // An upgrading user has already completed onboarding but has no engine
        // key yet — they must keep Whisper, not be moved onto Apple.
        let defaults = makeDefaults()
        defaults.set(true, forKey: "hasCompletedOnboarding")
        let store = SettingsStore(defaults: defaults)
        #expect(store.transcriptionEngine == .whisper)
    }

    @Test func enginePersistsAndReloads() {
        let defaults = makeDefaults()
        let store = SettingsStore(defaults: defaults)
        store.transcriptionEngine = .whisper
        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.transcriptionEngine == .whisper)
    }

    @Test func firesOnChangeForEngine() {
        let store = SettingsStore(defaults: makeDefaults())
        var changes: [SettingsStore.Change] = []
        store.onChange = { changes.append($0) }
        store.transcriptionEngine = .whisper
        #expect(changes == [.transcriptionEngine])
    }

    @Test func historyLimitMapping() {
        #expect(HistoryLimit.off.maxEntries == 0)
        #expect(HistoryLimit.ten.maxEntries == 10)
        #expect(HistoryLimit.fifty.maxEntries == 50)
        #expect(HistoryLimit.twoHundred.maxEntries == 200)
        #expect(HistoryLimit.unlimited.maxEntries == nil)
        #expect(!HistoryLimit.off.savesHistory)
        #expect(HistoryLimit.ten.savesHistory)
    }
}
