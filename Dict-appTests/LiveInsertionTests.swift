import Testing
@testable import Dict_app

struct LiveInsertionPlanTests {
    @Test func appendsWhenTargetExtendsTyped() {
        let edit = LiveInsertionPlan.edit(from: "hello there", to: "hello there friend")
        #expect(edit == .init(deleteCount: 0, append: " friend"))
    }

    @Test func nothingWhenEqual() {
        #expect(LiveInsertionPlan.edit(from: "same", to: "same") == .none)
        #expect(LiveInsertionPlan.edit(from: "", to: "") == .none)
    }

    @Test func deletesTheDifferingTailOnly() {
        // The formatter capitalized and punctuated: keep the shared prefix.
        let edit = LiveInsertionPlan.edit(from: "Hello there how are you", to: "Hello there, how are you?")
        #expect(edit.deleteCount == "there how are you".count - "there".count)
        #expect(edit == .init(deleteCount: 12, append: ", how are you?"))
    }

    @Test func retypesEverythingWhenTheStartChanged() {
        let edit = LiveInsertionPlan.edit(from: "the cat", to: "The cat sat")
        #expect(edit == .init(deleteCount: 7, append: "The cat sat"))
    }

    @Test func cancelDeletesAll() {
        #expect(LiveInsertionPlan.edit(from: " typed words", to: "") == .init(deleteCount: 12, append: ""))
    }

    @Test func handlesEmojiAsSingleCharacters() {
        let edit = LiveInsertionPlan.edit(from: "ok 👍", to: "ok 👍 done")
        #expect(edit == .init(deleteCount: 0, append: " done"))
    }
}
