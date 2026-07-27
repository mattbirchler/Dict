import SwiftUI

struct OnboardingView: View {
    @Bindable var appState: AppState
    var onComplete: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text("Welcome to Dict")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Dict needs a few permissions to work. Grant each one below.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 16) {
                PermissionRow(
                    title: "Microphone",
                    description: "Record your voice for dictation",
                    systemImage: "mic.fill",
                    isGranted: appState.permissionChecker.microphoneGranted,
                    action: {
                        print("[Onboarding] Microphone Grant button tapped")
                        if appState.permissionChecker.microphoneNotDetermined {
                            Task { await appState.permissionChecker.requestMicrophone() }
                        } else {
                            print("[Onboarding] Mic already denied, opening System Settings")
                            appState.permissionChecker.openMicrophoneSettings()
                        }
                    },
                    openSettings: appState.permissionChecker.openMicrophoneSettings
                )

                PermissionRow(
                    title: "Accessibility",
                    description: "Detect key presses and paste text globally",
                    systemImage: "hand.raised.fill",
                    isGranted: appState.permissionChecker.accessibilityGranted,
                    action: {
                        print("[Onboarding] Accessibility Grant button tapped")
                        appState.permissionChecker.openAccessibilitySettings()
                    },
                    openSettings: appState.permissionChecker.openAccessibilitySettings
                )

                PermissionRow(
                    title: "Speech Recognition",
                    description: "Transcribe your voice on-device",
                    systemImage: "waveform.badge.mic",
                    isGranted: appState.permissionChecker.speechRecognitionGranted,
                    action: {
                        print("[Onboarding] Speech Recognition Grant button tapped")
                        Task { await appState.permissionChecker.requestSpeechRecognition() }
                    },
                    openSettings: appState.permissionChecker.openSpeechRecognitionSettings
                )

                // Transcription engine picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Transcription engine")
                        .font(.headline)
                    Picker("", selection: Binding(
                        get: { appState.settings.transcriptionEngine },
                        set: { appState.settings.transcriptionEngine = $0 }
                    )) {
                        ForEach(TranscriptionEngineChoice.allCases, id: \.self) { choice in
                            Text(choice.displayName).tag(choice)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text(appState.settings.transcriptionEngine.blurb)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.05)))

                // Adaptive engine-readiness row
                HStack(spacing: 12) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title2)
                        .foregroundStyle(appState.isEngineReady ? .green : .secondary)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(appState.settings.transcriptionEngine.modelDisplayName)
                            .font(.headline)
                        if appState.isEngineReady {
                            Text("Ready")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if appState.isPreparingEngine {
                            if appState.engineNeedsDownload {
                                ProgressView(value: appState.engineDownloadProgress)
                                    .progressViewStyle(.linear)
                            } else {
                                Text("Preparing…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else if let downloadPrompt = appState.settings.transcriptionEngine.downloadPrompt,
                                  appState.engineNeedsDownload {
                            Text(downloadPrompt)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Preparing…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if appState.isEngineReady {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.title2)
                    } else if appState.isPreparingEngine {
                        ProgressView()
                            .controlSize(.small)
                    } else if appState.engineNeedsDownload {
                        Button("Download") { appState.prepareEngine() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(appState.isEngineReady ? Color.green.opacity(0.05) : Color.secondary.opacity(0.05))
                )
            }
            .padding(.horizontal)

            Spacer()

            Button("Get Started") {
                appState.hasCompletedOnboarding = true
                onComplete()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!appState.isEngineReady)

            if !appState.permissionChecker.allGranted || !appState.isEngineReady {
                Text("Grant all permissions and download the model to continue")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(32)
        .frame(width: 480, height: 580)
        .onAppear {
            appState.permissionChecker.checkAll()
            if appState.permissionChecker.microphoneNotDetermined {
                Task { await appState.permissionChecker.requestMicrophone() }
            }
            appState.refreshEngineReadiness()
            if appState.canAutoPrepare && !appState.isEngineReady && !appState.isPreparingEngine {
                appState.prepareEngine()
            }
        }
        .onChange(of: appState.settings.transcriptionEngine) { _, _ in
            appState.refreshEngineReadiness()
            if appState.canAutoPrepare && !appState.isEngineReady && !appState.isPreparingEngine {
                appState.prepareEngine()
            }
        }
    }
}

struct PermissionRow: View {
    let title: String
    let description: String
    let systemImage: String
    let isGranted: Bool
    let action: () -> Void
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(isGranted ? .green : .secondary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title2)
            } else {
                Button("Grant") {
                    print("[PermissionRow] '\(title)' Grant button action fired")
                    action()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isGranted ? Color.green.opacity(0.05) : Color.secondary.opacity(0.05))
        )
    }
}

final class OnboardingWindowController {
    private var window: NSWindow?

    func show(appState: AppState) {
        guard window == nil else {
            window?.makeKeyAndOrderFront(nil)
            return
        }

        let onboardingView = OnboardingView(appState: appState) { [weak self] in
            self?.close()
        }

        let hostingController = NSHostingController(rootView: onboardingView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Dict Setup"
        window.styleMask = [.titled, .closable]
        window.center()
        window.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }

    func close() {
        window?.close()
        window = nil
    }
}
