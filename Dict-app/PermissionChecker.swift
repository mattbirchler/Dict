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
        print("[PermissionChecker] checkAll()")
        checkMicrophone()
        checkAccessibility()
        checkSpeechRecognition()
        print("[PermissionChecker] mic=\(microphoneGranted) accessibility=\(accessibilityGranted) speech=\(speechRecognitionGranted)")
    }

    var microphoneNotDetermined: Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        print("[PermissionChecker] microphoneNotDetermined check: status=\(status.rawValue)")
        return status == .notDetermined
    }

    func checkMicrophone() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        print("[PermissionChecker] checkMicrophone: status=\(status.rawValue) (0=notDetermined, 1=restricted, 2=denied, 3=authorized)")
        microphoneGranted = status == .authorized
    }

    func checkAccessibility() {
        accessibilityGranted = AXIsProcessTrusted()
        print("[PermissionChecker] checkAccessibility: \(accessibilityGranted)")
    }

    func checkSpeechRecognition() {
        let status = SFSpeechRecognizer.authorizationStatus()
        print("[PermissionChecker] checkSpeechRecognition: status=\(status.rawValue) (0=notDetermined, 1=denied, 2=restricted, 3=authorized)")
        speechRecognitionGranted = status == .authorized
    }

    func requestMicrophone() async {
        let currentStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        print("[PermissionChecker] requestMicrophone called. Current status=\(currentStatus.rawValue)")
        NSApp.activate(ignoringOtherApps: true)
        print("[PermissionChecker] Calling AVCaptureDevice.requestAccess(for: .audio)...")
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        print("[PermissionChecker] requestAccess returned: granted=\(granted)")
        microphoneGranted = granted
    }

    func requestSpeechRecognition() async {
        print("[PermissionChecker] requestSpeechRecognition called")
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                print("[PermissionChecker] SFSpeechRecognizer authorization callback: status=\(status.rawValue)")
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
