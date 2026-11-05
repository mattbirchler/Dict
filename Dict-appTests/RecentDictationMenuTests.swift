import Foundation
import Testing
@testable import Dict_app

struct RecentDictationMenuTests {
    @Test func shortTextIsUnchanged() {
        #expect(MenuBarManager.recentTitle(for: "Hello there.") == "Hello there.")
    }

    @Test func lineBreaksAndRunsOfSpacesCollapse() {
        #expect(MenuBarManager.recentTitle(for: "First line\n\nsecond   line\t") == "First line second line")
    }

    @Test func longTextIsCutWithAnEllipsis() {
        let text = String(repeating: "word ", count: 30)
        let title = MenuBarManager.recentTitle(for: text)
        #expect(title.count <= MenuBarManager.recentTitleLength)
        #expect(title.hasSuffix("…"))
        #expect(!title.hasSuffix(" …"))
    }
}
