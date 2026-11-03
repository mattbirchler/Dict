import Foundation
import Testing
@testable import Dict_app

struct OnboardingFlowTests {
    @Test func stepsRunWelcomeToDone() {
        #expect(OnboardingFlow.steps.first == .welcome)
        #expect(OnboardingFlow.steps.last == .done)
        #expect(OnboardingFlow.next(after: .welcome) == .listen)
        #expect(OnboardingFlow.next(after: .done) == nil)
        #expect(OnboardingFlow.previous(before: .welcome) == nil)
        #expect(OnboardingFlow.previous(before: .listen) == .welcome)
    }

    @Test func listenNeedsMicAndSpeechForApple() {
        var status = OnboardingStatus(microphoneGranted: true, speechRecognitionGranted: false, speechRecognitionNeeded: true)
        #expect(!OnboardingFlow.canContinue(from: .listen, status: status))
        status.speechRecognitionGranted = true
        #expect(OnboardingFlow.canContinue(from: .listen, status: status))
    }

    @Test func listenNeedsOnlyMicForParakeet() {
        let status = OnboardingStatus(microphoneGranted: true, speechRecognitionGranted: false, speechRecognitionNeeded: false)
        #expect(OnboardingFlow.canContinue(from: .listen, status: status))
        #expect(!OnboardingFlow.canContinue(from: .listen, status: OnboardingStatus(speechRecognitionNeeded: false)))
    }

    @Test func accessibilityGatesItsOwnScreenOnly() {
        let status = OnboardingStatus()
        #expect(!OnboardingFlow.canContinue(from: .accessibility, status: status))
        #expect(OnboardingFlow.canContinue(from: .welcome, status: status))
        #expect(OnboardingFlow.canContinue(from: .chooseKey, status: status))
        #expect(OnboardingFlow.canContinue(from: .tryIt, status: status), "the test is optional")
        #expect(OnboardingFlow.canContinue(from: .accuracy, status: status), "the download is optional")
        #expect(OnboardingFlow.canContinue(from: .done, status: status))
    }

    @Test func rerunOpensOnTheFirstMissingPermission() {
        #expect(OnboardingFlow.firstUnsatisfiedStep(status: OnboardingStatus()) == .listen)
        let micOnly = OnboardingStatus(microphoneGranted: true, speechRecognitionGranted: true)
        #expect(OnboardingFlow.firstUnsatisfiedStep(status: micOnly) == .accessibility)
        let all = OnboardingStatus(microphoneGranted: true, speechRecognitionGranted: true, accessibilityGranted: true)
        #expect(OnboardingFlow.firstUnsatisfiedStep(status: all) == .welcome)
    }

    @Test func satisfiedStepsShowDoneState() {
        let all = OnboardingStatus(microphoneGranted: true, speechRecognitionGranted: true, accessibilityGranted: true, parakeetReady: true)
        #expect(OnboardingFlow.isSatisfied(.listen, status: all))
        #expect(OnboardingFlow.isSatisfied(.accessibility, status: all))
        #expect(OnboardingFlow.isSatisfied(.accuracy, status: all))
        #expect(!OnboardingFlow.isSatisfied(.welcome, status: all))
    }
}
