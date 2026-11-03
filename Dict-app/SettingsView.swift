import SwiftUI
import Sparkle
import Combine
import os

/// Bridges Sparkle's KVO-based `canCheckForUpdates` into SwiftUI so the
/// "Check for Updates…" button can dim while a check is already in flight.
final class UpdaterViewModel: ObservableObject {
    @Published var canCheckForUpdates = false
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        updater.checkForUpdates()
    }
}

struct GeneralSettingsTab: View {
    @Bindable var settings: SettingsStore
    var appState: AppState
    @State private var loginItem = LoginItemManager()
    @State private var inputDevices: [AudioInputDevice] = []

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $loginItem.isEnabled)
                if loginItem.requiresApproval {
                    HStack {
                        Text("Waiting for approval in System Settings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Open Login Items…") {
                            loginItem.openLoginItemsSettings()
                        }
                        .controlSize(.small)
                    }
                }
                if let error = loginItem.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Picker("Dictation hotkey", selection: $settings.hotkey) {
                    ForEach(HotkeyChoice.allCases, id: \.self) { choice in
                        Text(choice.displayName).tag(choice)
                    }
                }
                if settings.hotkey == .fn {
                    Text("If pressing 🌐 opens the emoji picker, set “Press 🌐 key to” to “Do Nothing” in System Settings > Keyboard.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Picker("Activation", selection: $settings.activationMode) {
                    ForEach(ActivationMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                Text(activationCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Microphone", selection: $settings.inputDevice) {
                    Text(InputDeviceChoice.automatic.displayName).tag(InputDeviceChoice.automatic)
                    Text(InputDeviceChoice.systemDefault.displayName).tag(InputDeviceChoice.systemDefault)
                    if !inputDevices.isEmpty {
                        Divider()
                        ForEach(inputDevices) { device in
                            Text(device.name).tag(InputDeviceChoice.device(uid: device.uid))
                        }
                    }
                    if case .device(let uid) = settings.inputDevice, !inputDevices.contains(where: { $0.uid == uid }) {
                        Text("Unplugged microphone").tag(settings.inputDevice)
                    }
                }
                Text("Automatic uses your system microphone, but switches to the built-in one when a Bluetooth headset is the default. Bluetooth headsets record at low quality and take over audio output.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Dictation panel") {
                HUDSchemePicker(selection: $settings.hudColorScheme)
                Text("The colors the panel lights up in while you dictate.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Transcription engine", selection: $settings.transcriptionEngine) {
                    ForEach(TranscriptionEngineChoice.allCases, id: \.self) { choice in
                        Text(choice.displayName).tag(choice)
                    }
                }
                Text(engineStatusCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let downloadPrompt = settings.transcriptionEngine.downloadPrompt,
                   appState.engineNeedsDownload,
                   !appState.isEngineReady, !appState.isPreparingEngine {
                    Button(downloadPrompt) { appState.prepareEngine() }
                        .controlSize(.small)
                }
                if appState.isPreparingEngine && appState.engineNeedsDownload {
                    ProgressView(value: appState.engineDownloadProgress)
                        .progressViewStyle(.linear)
                }
            }

            Section {
                Toggle("Format transcripts", isOn: $settings.isFormattingEnabled)
                Text("Add punctuation and capitalization with the on-device Apple Intelligence model. In coding and terminal apps, it also fixes technical terms like \u{201C}main\u{201D} and \u{201C}git.\u{201D} Parakeet punctuates on its own, so with Parakeet this only runs in coding and terminal apps. Turn off to insert the raw transcript as spoken.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Add a space before dictation when needed", isOn: $settings.smartLeadingSpace)
                Text("Checks the character before the cursor and adds a space if the text would otherwise run into the previous word. Some apps, including many terminals, don\u{2019}t expose this; there nothing is added.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Add a space after each dictation", isOn: $settings.appendTrailingSpace)
                Text("Inserts a space after each result so you can dictate several sentences in separate chunks without pressing space between them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            loginItem.refresh()
            inputDevices = AudioInputDevices.all()
        }
    }

    private var engineStatusCaption: String {
        if appState.isPreparingEngine {
            return appState.engineNeedsDownload ? "Downloading…" : "Preparing…"
        }
        if appState.isEngineReady {
            return "\(settings.transcriptionEngine.displayName) is ready. \(settings.transcriptionEngine.blurb)"
        }
        return settings.transcriptionEngine.blurb
    }

    private var activationCaption: String {
        switch settings.activationMode {
        case .holdToTalk:
            "Hold the hotkey and speak; release to insert. Tap Space while holding to go hands-free, then press the hotkey to finish."
        case .toggle:
            "Press the hotkey to start recording; press it again to stop and insert."
        }
    }
}

struct AboutSettingsTab: View {
    @StateObject private var updaterViewModel: UpdaterViewModel
    @State private var logStatus: String?
    @State private var logStatusTask: Task<Void, Never>?

    init(updater: SPUUpdater) {
        self._updaterViewModel = StateObject(wrappedValue: UpdaterViewModel(updater: updater))
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(version) (\(build))"
    }

    /// Puts the last hour of Dict's log on the clipboard for a bug report.
    private func copyDiagnosticLog() {
        do {
            let log = try DiagnosticLog.recent()
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(log, forType: .string)
            logStatus = "Copied. Paste it into a bug report."
        } catch {
            logStatus = "Couldn't read the log: \(error.localizedDescription)"
        }
        logStatusTask?.cancel()
        logStatusTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            logStatus = nil
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            Text("Dict")
                .font(.title2.bold())
            Text(versionString)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("100% on-device: transcription, formatting, and history never leave this Mac.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Button("Check for Updates…") {
                updaterViewModel.checkForUpdates()
            }
            .disabled(!updaterViewModel.canCheckForUpdates)

            Button("Copy Diagnostic Log") { copyDiagnosticLog() }
            if let logStatus {
                Text(logStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Built with FluidAudio and Sparkle.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}
