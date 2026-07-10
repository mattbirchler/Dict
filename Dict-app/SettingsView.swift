import SwiftUI
import Sparkle

struct SettingsView: View {
    @Bindable var appState: AppState
    let updater: SPUUpdater

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsTab(settings: appState.settings)
            }
            Tab("History", systemImage: "clock.arrow.circlepath") {
                HistorySettingsTab(
                    settings: appState.settings,
                    historyStore: appState.pipeline.historyStore
                )
            }
            Tab("About", systemImage: "info.circle") {
                AboutSettingsTab(updater: updater)
            }
        }
        .frame(width: 480)
    }
}

struct GeneralSettingsTab: View {
    @Bindable var settings: SettingsStore
    @State private var loginItem = LoginItemManager()

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
                Toggle("Format transcripts", isOn: $settings.isFormattingEnabled)
                Text("Add punctuation and capitalization with the on-device Apple Intelligence model. Turn off to insert the raw transcript as spoken.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { loginItem.refresh() }
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

struct HistorySettingsTab: View {
    @Bindable var settings: SettingsStore
    let historyStore: HistoryStore
    @State private var confirmingClear = false

    var body: some View {
        Form {
            Section {
                Picker("Keep history", selection: $settings.historyLimit) {
                    ForEach(HistoryLimit.allCases, id: \.self) { limit in
                        Text(limit.displayName).tag(limit)
                    }
                }
                Text("Transcriptions are stored only on this Mac. “Off” stops saving new transcriptions; items already saved stay until you clear them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Clear History…", role: .destructive) {
                    confirmingClear = true
                }
                .confirmationDialog(
                    "Delete all saved transcriptions?",
                    isPresented: $confirmingClear
                ) {
                    Button("Clear History", role: .destructive) {
                        historyStore.clearAll()
                    }
                } message: {
                    Text("This removes every saved transcription from this Mac. It can't be undone.")
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct AboutSettingsTab: View {
    @StateObject private var updaterViewModel: UpdaterViewModel

    init(updater: SPUUpdater) {
        self._updaterViewModel = StateObject(wrappedValue: UpdaterViewModel(updater: updater))
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(version) (\(build))"
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

            Text("Built with WhisperKit and Sparkle.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}
