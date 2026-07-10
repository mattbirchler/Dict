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
                Text("History settings coming in Task 7")
            }
            Tab("About", systemImage: "info.circle") {
                Text("About coming in Task 7")
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
