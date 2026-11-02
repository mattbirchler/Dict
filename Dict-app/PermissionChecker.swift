import AppKit
import AVFoundation
import Speech
import os

@Observable
final class PermissionChecker {
    var microphoneGranted = false
    var accessibilityGranted = false
    var speechRecognitionGranted = false

    /// Whether everything `engine` needs has been granted. Speech
    /// Recognition only counts for engines that use it.
    func requiredGranted(for engine: TranscriptionEngineChoice) -> Bool {
        microphoneGranted && accessibilityGranted
            && (!engine.needsSpeechRecognitionPermission || speechRecognitionGranted)
    }

    func checkAll() {
        Log.permissions.debug("checkAll()")
        checkMicrophone()
        checkAccessibility()
        checkSpeechRecognition()
        Log.permissions.debug("mic=\(self.microphoneGranted, privacy: .public) accessibility=\(self.accessibilityGranted, privacy: .public) speech=\(self.speechRecognitionGranted, privacy: .public)")
    }

    var microphoneNotDetermined: Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        Log.permissions.debug("microphoneNotDetermined check: status=\(status.rawValue, privacy: .public)")
        return status == .notDetermined
    }

    func checkMicrophone() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        Log.permissions.debug("checkMicrophone: status=\(status.rawValue, privacy: .public) (0=notDetermined, 1=restricted, 2=denied, 3=authorized)")
        microphoneGranted = status == .authorized
    }

    func checkAccessibility() {
        accessibilityGranted = AXIsProcessTrusted()
        Log.permissions.debug("checkAccessibility: \(self.accessibilityGranted, privacy: .public)")
    }

    func checkSpeechRecognition() {
        let status = SFSpeechRecognizer.authorizationStatus()
        Log.permissions.debug("checkSpeechRecognition: status=\(status.rawValue, privacy: .public) (0=notDetermined, 1=denied, 2=restricted, 3=authorized)")
        speechRecognitionGranted = status == .authorized
    }

    func requestMicrophone() async {
        let currentStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        Log.permissions.debug("requestMicrophone called. Current status=\(currentStatus.rawValue, privacy: .public)")
        NSApp.activate(ignoringOtherApps: true)
        Log.permissions.debug("Calling AVCaptureDevice.requestAccess(for: .audio)...")
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        Log.permissions.debug("requestAccess returned: granted=\(granted, privacy: .public)")
        microphoneGranted = granted
    }

    func requestSpeechRecognition() async {
        Log.permissions.debug("requestSpeechRecognition called")
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                Log.permissions.debug("SFSpeechRecognizer authorization callback: status=\(status.rawValue, privacy: .public)")
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
