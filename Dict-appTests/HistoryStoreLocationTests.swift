import Foundation
import Testing
@testable import Dict_app

struct HistoryStoreLocationTests {
    @Test func historyLivesInDictsOwnFolder() {
        let support = URL(fileURLWithPath: "/Users/m/Library/Application Support")
        let url = HistoryStore.storeURL(applicationSupport: support)
        #expect(url.path == "/Users/m/Library/Application Support/Dict/History.store")
    }
}
