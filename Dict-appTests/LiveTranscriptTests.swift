import Testing
@testable import Dict_app

struct LiveTranscriptTests {
    @Test func firstDecodeIsAllTentative() {
        let live = LiveTranscript.comparing(previous: "", current: "So I think")
        #expect(live.confirmed == "")
        #expect(live.tentative == "So I think")
    }

    @Test func wordsBothDecodesAgreeOnAreConfirmed() {
        let live = LiveTranscript.comparing(previous: "So I think we", current: "So I think we should ship")
        #expect(live.confirmed == "So I think we")
        #expect(live.tentative == "should ship")
    }

    @Test func revisedWordAndEverythingAfterStaysTentative() {
        let live = LiveTranscript.comparing(previous: "Ship the new bill today", current: "Ship the new build today and")
        #expect(live.confirmed == "Ship the new")
        #expect(live.tentative == "build today and")
    }

    @Test func punctuationAndCaseChangesStillCountAsAgreement() {
        let live = LiveTranscript.comparing(previous: "we should ship", current: "We should ship. Tomorrow")
        #expect(live.confirmed == "We should ship.")
        #expect(live.tentative == "Tomorrow")
    }

    @Test func fullTextJoinsBothParts() {
        #expect(LiveTranscript(confirmed: "a b", tentative: "c").fullText == "a b c")
        #expect(LiveTranscript(confirmed: "", tentative: "c").fullText == "c")
        #expect(LiveTranscript().isEmpty)
    }
}
