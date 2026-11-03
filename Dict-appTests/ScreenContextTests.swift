import Testing
@testable import Dict_app

struct ScreenContextTests {
    @Test func picksNamesMidSentenceNotSentenceStarters() {
        let text = "Yesterday I talked to Priya about the launch. The plan is fine. Priya agreed."
        let terms = ScreenContext.extractTerms(from: text)
        #expect(terms.contains("Priya"))
        #expect(!terms.contains("Yesterday"))
        #expect(!terms.contains("The"))
    }

    @Test func picksIdentifiersAcronymsAndFiles() {
        let text = "Open main.swift and fix the JSON parsing in PipelineCoordinator, then rerun the v3 tests for user_id."
        let terms = ScreenContext.extractTerms(from: text)
        for expected in ["main.swift", "JSON", "PipelineCoordinator", "v3", "user_id"] {
            #expect(terms.contains(expected), "missing \(expected)")
        }
        #expect(!terms.contains("Open"))
    }

    @Test func repeatedSentenceStarterCountsAsAName() {
        let text = "Birchtree is the site. Birchtree started in 2010."
        #expect(ScreenContext.extractTerms(from: text).contains("Birchtree"))
    }

    @Test func mostFrequentFirstAndLimited() {
        let text = "Alpha met Beta. Then Beta met Gamma. Beta again, with Alpha."
        let terms = ScreenContext.extractTerms(from: text, limit: 2)
        #expect(terms == ["Beta", "Alpha"])
    }

    @Test func stripsPunctuationAndIgnoresNoise() {
        let text = "Email (Sanjay) today, \"Sanjay\" replied! Ok."
        let terms = ScreenContext.extractTerms(from: text)
        #expect(terms == ["Sanjay"])
        #expect(ScreenContext.extractTerms(from: "").isEmpty)
    }
}
