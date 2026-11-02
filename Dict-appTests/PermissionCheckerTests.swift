import Testing
@testable import Dict_app

struct PermissionCheckerTests {
    @Test func parakeetDoesNotNeedSpeechRecognition() {
        let checker = PermissionChecker()
        checker.microphoneGranted = true
        checker.accessibilityGranted = true
        checker.speechRecognitionGranted = false
        #expect(checker.requiredGranted(for: .parakeet))
        #expect(!checker.requiredGranted(for: .apple))
    }

    @Test func everyEngineNeedsMicrophoneAndAccessibility() {
        let checker = PermissionChecker()
        checker.microphoneGranted = true
        checker.accessibilityGranted = false
        checker.speechRecognitionGranted = true
        #expect(!checker.requiredGranted(for: .parakeet))
        #expect(!checker.requiredGranted(for: .apple))
    }

    @Test func onlyAppleNeedsSpeechRecognition() {
        #expect(TranscriptionEngineChoice.apple.needsSpeechRecognitionPermission)
        #expect(!TranscriptionEngineChoice.parakeet.needsSpeechRecognitionPermission)
    }
}
