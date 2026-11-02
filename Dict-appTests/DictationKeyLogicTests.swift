import Foundation
import Testing
@testable import Dict_app

struct DictationKeyLogicTests {
    private let t0 = ContinuousClock().now

    // MARK: Hold-to-talk (today's behavior)

    @Test func holdPressStartsRecording() {
        var logic = DictationKeyLogic(mode: .holdToTalk)
        #expect(logic.hotkeyDown(now: t0) == .start)
        #expect(logic.isRecording)
    }

    @Test func holdReleaseAfterThresholdStops() {
        var logic = DictationKeyLogic(mode: .holdToTalk)
        _ = logic.hotkeyDown(now: t0)
        #expect(logic.hotkeyUp(now: t0 + .milliseconds(200)) == .stop)
        #expect(!logic.isRecording)
    }

    @Test func holdShortTapCancels() {
        var logic = DictationKeyLogic(mode: .holdToTalk)
        _ = logic.hotkeyDown(now: t0)
        #expect(logic.hotkeyUp(now: t0 + .milliseconds(50)) == .cancel)
        #expect(!logic.isRecording)
    }

    @Test func duplicateDownEventsAreIgnoredWhileHeld() {
        var logic = DictationKeyLogic(mode: .holdToTalk)
        _ = logic.hotkeyDown(now: t0)
        #expect(logic.hotkeyDown(now: t0 + .milliseconds(10)) == nil)
    }

    // MARK: Refused starts (engine still loading)

    @Test func abandonedStartIgnoresReleaseAndSpace() {
        var logic = DictationKeyLogic(mode: .holdToTalk)
        #expect(logic.hotkeyDown(now: t0) == .start)
        logic.abandonStart()
        #expect(!logic.isRecording)
        #expect(logic.spaceDown() == nil)
        #expect(!logic.shouldSwallowSpace)
        #expect(logic.hotkeyUp(now: t0 + .milliseconds(50)) == nil)
        #expect(logic.hotkeyUp(now: t0 + .milliseconds(500)) == nil)
    }

    @Test func abandonedStartInToggleModeStartsAgainOnNextPress() {
        var logic = DictationKeyLogic(mode: .toggle)
        #expect(logic.hotkeyDown(now: t0) == .start)
        logic.abandonStart()
        _ = logic.hotkeyUp(now: t0 + .milliseconds(100))
        #expect(logic.hotkeyDown(now: t0 + .seconds(1)) == .start)
    }

    // MARK: Hands-free (Space while holding)

    @Test func spaceWhileHoldingEntersHandsFree() {
        var logic = DictationKeyLogic(mode: .holdToTalk)
        _ = logic.hotkeyDown(now: t0)
        #expect(logic.shouldSwallowSpace)
        #expect(logic.spaceDown() == .enterHandsFree)
        #expect(logic.handsFreeMode)
        #expect(!logic.shouldSwallowSpace)
    }

    @Test func handsFreeSurvivesKeyRelease() {
        var logic = DictationKeyLogic(mode: .holdToTalk)
        _ = logic.hotkeyDown(now: t0)
        _ = logic.spaceDown()
        #expect(logic.hotkeyUp(now: t0 + .milliseconds(500)) == nil)
        #expect(logic.isRecording)
    }

    @Test func hotkeyPressStopsHandsFree() {
        var logic = DictationKeyLogic(mode: .holdToTalk)
        _ = logic.hotkeyDown(now: t0)
        _ = logic.spaceDown()
        _ = logic.hotkeyUp(now: t0 + .milliseconds(500))
        #expect(logic.hotkeyDown(now: t0 + .seconds(2)) == .stop)
        #expect(!logic.isRecording)
        #expect(!logic.handsFreeMode)
    }

    @Test func spaceWhenNotRecordingDoesNothing() {
        var logic = DictationKeyLogic(mode: .holdToTalk)
        #expect(logic.spaceDown() == nil)
        #expect(!logic.shouldSwallowSpace)
    }

    // MARK: Toggle mode

    @Test func togglePressStartsThenStops() {
        var logic = DictationKeyLogic(mode: .toggle)
        #expect(logic.hotkeyDown(now: t0) == .start)
        #expect(logic.hotkeyUp(now: t0 + .milliseconds(80)) == nil)
        #expect(logic.isRecording)
        #expect(logic.hotkeyDown(now: t0 + .seconds(3)) == .stop)
        #expect(!logic.isRecording)
    }

    @Test func toggleIgnoresSpaceEntirely() {
        var logic = DictationKeyLogic(mode: .toggle)
        _ = logic.hotkeyDown(now: t0)
        _ = logic.hotkeyUp(now: t0 + .milliseconds(80))
        #expect(logic.spaceDown() == nil)
        #expect(!logic.shouldSwallowSpace)
    }

    // MARK: Reset (hotkey/mode changed or monitor uninstalled)

    @Test func resetWhileRecordingRequestsStop() {
        var logic = DictationKeyLogic(mode: .toggle)
        _ = logic.hotkeyDown(now: t0)
        #expect(logic.reset() == .stop)
        #expect(!logic.isRecording)
        #expect(!logic.handsFreeMode)
    }

    @Test func resetWhileIdleDoesNothing() {
        var logic = DictationKeyLogic(mode: .holdToTalk)
        #expect(logic.reset() == nil)
    }

    // MARK: Escape

    @Test func escapeCancelsHandsFreeAndNextPressStartsFresh() {
        var logic = DictationKeyLogic(mode: .holdToTalk)
        _ = logic.hotkeyDown(now: t0)
        _ = logic.spaceDown()
        _ = logic.hotkeyUp(now: t0 + .milliseconds(300))
        #expect(logic.escapeDown() == .cancel)
        #expect(!logic.isRecording)
        #expect(!logic.handsFreeMode)
        #expect(logic.hotkeyDown(now: t0 + .seconds(2)) == .start)
    }

    @Test func escapeWhileHoldingCancelsAndReleaseDoesNothing() {
        var logic = DictationKeyLogic(mode: .holdToTalk)
        _ = logic.hotkeyDown(now: t0)
        #expect(logic.escapeDown() == .cancel)
        #expect(logic.hotkeyUp(now: t0 + .milliseconds(500)) == nil)
    }

    @Test func escapeCancelsToggleRecording() {
        var logic = DictationKeyLogic(mode: .toggle)
        _ = logic.hotkeyDown(now: t0)
        _ = logic.hotkeyUp(now: t0 + .milliseconds(100))
        #expect(logic.escapeDown() == .cancel)
        _ = logic.hotkeyDown(now: t0 + .seconds(1))
        #expect(logic.isRecording)
    }

    @Test func escapePassesThroughWhenIdle() {
        var logic = DictationKeyLogic(mode: .holdToTalk)
        #expect(logic.escapeDown() == nil)
    }
}
