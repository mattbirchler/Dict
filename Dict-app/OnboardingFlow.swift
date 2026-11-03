import Foundation

/// The screens of first-run setup, in order. One idea per screen.
enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    /// Microphone, plus Speech Recognition when the engine needs it.
    case listen
    case accessibility
    case chooseKey
    case tryIt
    /// Offer the Parakeet download.
    case accuracy
    case done

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome: "Welcome"
        case .listen: "Listening"
        case .accessibility: "Typing for you"
        case .chooseKey: "Your key"
        case .tryIt: "Try it"
        case .accuracy: "Better accuracy"
        case .done: "Ready"
        }
    }
}

/// What the flow knows about the Mac right now; the views read it from
/// AppState, the tests build it by hand.
struct OnboardingStatus: Equatable {
    var microphoneGranted = false
    var speechRecognitionGranted = false
    var speechRecognitionNeeded = true
    var accessibilityGranted = false
    var engineReady = false
    var parakeetReady = false
}

/// Pure rules for moving through setup.
enum OnboardingFlow {
    static let steps = OnboardingStep.allCases

    /// Whether Continue is enabled on `step`. Permissions the app can't
    /// work without gate their own screen; everything else lets people
    /// move on.
    static func canContinue(from step: OnboardingStep, status: OnboardingStatus) -> Bool {
        switch step {
        case .listen:
            status.microphoneGranted && (!status.speechRecognitionNeeded || status.speechRecognitionGranted)
        case .accessibility:
            status.accessibilityGranted
        case .welcome, .chooseKey, .tryIt, .accuracy, .done:
            true
        }
    }

    /// Whether a step's requirement is already met, so the screen shows
    /// its done state instead of asking.
    static func isSatisfied(_ step: OnboardingStep, status: OnboardingStatus) -> Bool {
        switch step {
        case .listen, .accessibility: canContinue(from: step, status: status)
        case .accuracy: status.parakeetReady
        default: false
        }
    }

    static func next(after step: OnboardingStep) -> OnboardingStep? {
        OnboardingStep(rawValue: step.rawValue + 1)
    }

    static func previous(before step: OnboardingStep) -> OnboardingStep? {
        OnboardingStep(rawValue: step.rawValue - 1)
    }

    /// Where a re-run of setup should open: the first screen whose
    /// requirement isn't met, or Welcome when everything is granted.
    static func firstUnsatisfiedStep(status: OnboardingStatus) -> OnboardingStep {
        for step in [OnboardingStep.listen, .accessibility] where !canContinue(from: step, status: status) {
            return step
        }
        return .welcome
    }
}
