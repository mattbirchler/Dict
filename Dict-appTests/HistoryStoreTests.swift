import Foundation
import Testing
@testable import Dict_app

@MainActor
struct HistoryStoreTests {
    private func makeStore() -> HistoryStore {
        HistoryStore(inMemory: true)
    }

    /// Distinct, ordered timestamps so sort order is deterministic.
    private func fill(_ store: HistoryStore, count: Int) {
        let base = Date(timeIntervalSince1970: 1_000_000)
        for i in 0..<count {
            store.save(cleanedText: "entry \(i)", timestamp: base.addingTimeInterval(Double(i)))
        }
    }

    @Test func savesAndPrunesToLimit() {
        let store = makeStore()
        store.limit = .ten
        fill(store, count: 12)
        #expect(store.recentEntries.count == 10)
        #expect(store.recentEntries.first?.cleanedText == "entry 11")
        #expect(store.recentEntries.last?.cleanedText == "entry 2")
    }

    @Test func offMeansNothingIsSaved() {
        let store = makeStore()
        store.limit = .off
        fill(store, count: 3)
        #expect(store.recentEntries.isEmpty)
    }

    @Test func offKeepsExistingEntries() {
        let store = makeStore()
        fill(store, count: 5)
        store.limit = .off
        #expect(store.recentEntries.count == 5)
    }

    @Test func loweringLimitPrunesImmediately() {
        let store = makeStore()
        fill(store, count: 30)
        #expect(store.recentEntries.count == 30)
        store.limit = .ten
        #expect(store.recentEntries.count == 10)
        #expect(store.recentEntries.first?.cleanedText == "entry 29")
    }

    @Test func unlimitedNeverPrunes() {
        let store = makeStore()
        store.limit = .unlimited
        fill(store, count: 60)
        #expect(store.recentEntries.count == 60)
    }

    @Test func clearAllDeletesEverything() {
        let store = makeStore()
        fill(store, count: 8)
        store.clearAll()
        #expect(store.recentEntries.isEmpty)
    }
}
