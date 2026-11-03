import SwiftUI
import AppKit
import Sparkle

/// Which section of the main window is showing. The menu bar opens the window
/// directly to one of these.
enum MainSection: Hashable {
    case history
    case general
    case replacements
    case about
}

/// Drives the main window's sidebar selection. Held by MainWindowController so
/// it can switch sections on an already-open window.
@Observable
final class MainWindowModel {
    var section: MainSection = .history
}

/// The app's one real window: a sidebar with the transcription History and the
/// Settings sections. Replaces both the old menu-bar popover (history list) and
/// the standalone Settings window.
struct MainWindow: View {
    let appState: AppState
    let updater: SPUUpdater
    @Bindable var model: MainWindowModel

    var body: some View {
        NavigationSplitView {
            List(selection: sidebarSelection) {
                Label("History", systemImage: "clock.arrow.circlepath")
                    .tag(MainSection.history)

                Section("Settings") {
                    Label("General", systemImage: "gearshape")
                        .tag(MainSection.general)
                    Label("Replacements", systemImage: "character.cursor.ibeam")
                        .tag(MainSection.replacements)
                    Label("About", systemImage: "info.circle")
                        .tag(MainSection.about)
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } detail: {
            switch model.section {
            case .history:
                HistoryView(appState: appState)
            case .general:
                GeneralSettingsTab(settings: appState.settings, appState: appState)
                    .navigationTitle("General")
            case .replacements:
                ReplacementsView(settings: appState.settings)
                    .navigationTitle("Replacements")
            case .about:
                AboutSettingsTab(settings: appState.settings, updater: updater)
                    .navigationTitle("About")
            }
        }
    }

    /// List selection is optional; keep the model's non-optional section in
    /// sync while ignoring deselection.
    private var sidebarSelection: Binding<MainSection?> {
        Binding(
            get: { model.section },
            set: { if let new = $0 { model.section = new } }
        )
    }
}

/// The transcription history: the list plus its retention controls, all in one
/// place (Keep-history picker and Clear live here, not in Settings).
struct HistoryView: View {
    let appState: AppState
    @Bindable var settings: SettingsStore
    @State private var confirmingClear = false

    init(appState: AppState) {
        self.appState = appState
        self.settings = appState.settings
    }

    private var store: HistoryStore { appState.pipeline.historyStore }

    var body: some View {
        VStack(spacing: 0) {
            if appState.stats.stats.dictations > 0 {
                StatsHeader(stats: appState.stats.stats, scheme: settings.hudColorScheme)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
            }
            if store.recentEntries.isEmpty {
                ContentUnavailableView(
                    "No Transcriptions Yet",
                    systemImage: "waveform",
                    description: Text("Text you dictate will show up here.")
                )
            } else {
                List {
                    ForEach(store.recentEntries) { entry in
                        HistoryEntryRow(entry: entry)
                    }
                }
            }
        }
        .navigationTitle("History")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    confirmingClear = true
                } label: {
                    Label("Clear History", systemImage: "trash")
                }
                .disabled(store.recentEntries.isEmpty)
                .help("Delete all saved transcriptions")
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                Picker("Keep", selection: $settings.historyLimit) {
                    ForEach(HistoryLimit.allCases, id: \.self) { limit in
                        Text(limit.displayName).tag(limit)
                    }
                }
                .fixedSize()
                .help("Off stops saving new transcriptions; existing ones stay until cleared.")

                Spacer()

                Text("Stored only on this Mac")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .confirmationDialog(
            "Delete all saved transcriptions?",
            isPresented: $confirmingClear
        ) {
            Button("Clear History", role: .destructive) {
                store.clearAll()
            }
        } message: {
            Text("This removes every saved transcription from this Mac. It can't be undone.")
        }
    }
}

struct HistoryEntryRow: View {
    let entry: TranscriptionEntry

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.cleanedText)
                    .lineLimit(4)
                    .textSelection(.enabled)
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
            }
            .buttonStyle(.borderless)
            .help("Copy to clipboard")
        }
        .padding(.vertical, 4)
    }
}
