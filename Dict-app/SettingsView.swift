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
                    ForEach(HotkeyChoice.presets, id: \.self) { choice in
                        Text(choice.displayName).tag(choice)
                    }
                    if settings.hotkey.isCustom {
                        Divider()
                        Text(settings.hotkey.displayName).tag(settings.hotkey)
                    }
                }
                LabeledContent("Or any key combination") {
                    ShortcutRecorder(hotkey: $settings.hotkey)
                }
                Text("Click the recorder, then press the keys you want, such as \u{2325}Space or F18. Modifier keys on their own are the choices above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                Toggle("Play sounds", isOn: $settings.playsSounds)
                Text("A short tone when recording starts, when it stops, and when the text goes in.")
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
                Picker("Dictation style", selection: $settings.dictationStyle) {
                    ForEach(DictationStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                Text(settings.dictationStyle.blurb + (settings.dictationStyle == .verbatim ? "" : " Uses the on-device Apple Intelligence model; without it, only ums and repeated words are dropped."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
    var settings: SettingsStore
    @StateObject private var updaterViewModel: UpdaterViewModel
    @State private var logStatus: String?
    @State private var logStatusTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let started = Date()

    init(settings: SettingsStore, updater: SPUUpdater) {
        self.settings = settings
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
            hero
                .padding(.bottom, 8)

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

    /// The HUD's panel, blown up: icon, name and version over a live grid.
    private var hero: some View {
        let scheme = settings.hudColorScheme
        return TimelineView(.periodic(from: .now, by: reduceMotion ? 3600 : 0.085)) { timeline in
            let t = timeline.date.timeIntervalSince(started)
            HStack(spacing: 18) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 6) {
                    Text("DICT")
                        .font(HUDFont.label(22, weight: .bold))
                        .tracking(4)
                        .foregroundStyle(scheme.text)
                    Text(versionString.uppercased())
                        .font(HUDFont.label(10.5, weight: .medium))
                        .tracking(1.6)
                        .foregroundStyle(scheme.accent.opacity(0.85))
                }
                Spacer(minLength: 12)
                DotMatrix(
                    spectrum: HUDPreview.sampleSpectrum(at: t),
                    isLive: true,
                    scheme: scheme,
                    phase: timeline.date.timeIntervalSinceReferenceDate
                )
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .frame(maxWidth: 420)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: [scheme.pillTop, scheme.pillBottom], startPoint: .top, endPoint: .bottom))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [scheme.glow.opacity(0.45), Color.white.opacity(0.06), scheme.glow.opacity(0.12)], startPoint: .top, endPoint: .bottom),
                        lineWidth: 1
                    )
            }
            .shadow(color: scheme.glow.opacity(0.18), radius: 22)
            .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
        }
    }
}
