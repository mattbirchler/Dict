import SwiftUI

struct MenuBarPopover: View {
    @Bindable var appState: AppState
    var onShowOnboarding: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Enable/disable toggle
            Toggle("Dictation Enabled", isOn: $appState.isEnabled)
                .toggleStyle(.switch)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider()

            Picker("Transcription", selection: $appState.transcriptionEngine) {
                ForEach(TranscriptionEngine.allCases, id: \.self) { engine in
                    Text(engine.displayName).tag(engine)
                }
            }
            .pickerStyle(.menu)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            if appState.isLoadingWhisper {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Downloading WhisperKit model…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ProgressView(value: appState.whisperDownloadProgress)
                        .progressViewStyle(.linear)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            Toggle("AI Cleanup", isOn: $appState.aiCleanupEnabled)
                .toggleStyle(.switch)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .disabled(!appState.foundationModelsAvailable)

            Divider()

            // Permission warning
            if !appState.permissionChecker.allGranted {
                Button(action: onShowOnboarding) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text("Missing permissions — click to fix")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.yellow.opacity(0.1))
                }
                .buttonStyle(.plain)

                Divider()
            }

            // Foundation Models warning
            if !appState.foundationModelsAvailable {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text("AI cleanup unavailable on this system")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                Divider()
            }

            // Status
            if appState.isProcessing {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Processing…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                Divider()
            }

            if let error = appState.lastError {
                HStack {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                Divider()
            }

            // History
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if appState.pipeline.historyStore.recentEntries.isEmpty {
                        Text("No transcriptions yet")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                    } else {
                        ForEach(appState.pipeline.historyStore.recentEntries) { entry in
                            HistoryEntryRow(entry: entry)
                            Divider().padding(.leading, 16)
                        }
                    }
                }
            }
            .frame(maxHeight: 300)

            Divider()

            // Quit
            Button("Quit Dict") {
                NSApp.terminate(nil)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .buttonStyle(.plain)
        }
        .frame(width: 320)
    }
}

struct HistoryEntryRow: View {
    let entry: TranscriptionEntry

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.cleanedText)
                    .lineLimit(3)
                    .font(.body)
                Text(entry.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.cleanedText, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Copy to clipboard")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
