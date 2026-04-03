import AppKit
import AVFoundation
import Speech

@Observable
final class PermissionChecker {
    var microphoneGranted = false
    var accessibilityGranted = false
    var speechRecognitionGranted = false

    var allGranted: Bool {
        microphoneGranted && accessibilityGranted && speechRecognitionGranted
    }

    func checkAll() {
        checkMicrophone()
        checkAccessibility()
        checkSpeechRecognition()
    }

    func checkMicrophone() {
        microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    func checkAccessibility() {
        accessibilityGranted = AXIsProcessTrusted()
    }

    func checkSpeechRecognition() {
        speechRecognitionGranted = SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    func requestMicrophone() async {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        microphoneGranted = granted
    }

    func requestSpeechRecognition() async {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                Task { @MainActor in
                    self.speechRecognitionGranted = (status == .authorized)
                    continuation.resume()
                }
            }
        }
    }

    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    func openMicrophoneSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        NSWorkspace.shared.open(url)
    }

    func openSpeechRecognitionSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")!
        NSWorkspace.shared.open(url)
    }
}
