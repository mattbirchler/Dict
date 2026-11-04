import SwiftUI
import AppKit
import Sparkle

/// Which section of the main window is showing. The menu bar opens the window
/// directly to one of these.
enum MainSection: Hashable {
    case history
    case general
    case replacements
    case license
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
        let scheme = appState.settings.hudColorScheme
        NavigationSplitView {
            List {
                SidebarRow(title: "History", systemImage: "clock.arrow.circlepath", section: .history, model: model, scheme: scheme)
                Section {
                    SidebarRow(title: "General", systemImage: "gearshape", section: .general, model: model, scheme: scheme)
                    SidebarRow(title: "Replacements", systemImage: "character.cursor.ibeam", section: .replacements, model: model, scheme: scheme)
                    SidebarRow(title: "License", systemImage: "key", section: .license, model: model, scheme: scheme)
                    SidebarRow(title: "About", systemImage: "info.circle", section: .about, model: model, scheme: scheme)
                } header: {
                    Text("SETTINGS")
                        .font(HUDFont.label(10, weight: .semibold))
                        .tracking(1.6)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(.downArrow) { model.section = Self.step(model.section, by: 1); return .handled }
            .onKeyPress(.upArrow) { model.section = Self.step(model.section, by: -1); return .handled }
        } detail: {
            Group {
            switch model.section {
            case .history:
                HistoryView(appState: appState)
            case .general:
                GeneralSettingsTab(settings: appState.settings, appState: appState)
                    .navigationTitle("General")
            case .replacements:
                ReplacementsView(settings: appState.settings)
                    .navigationTitle("Replacements")
            case .license:
                LicenseView(license: appState.license, scheme: scheme)
                    .navigationTitle("License")
            case .about:
                AboutSettingsTab(settings: appState.settings, updater: updater)
                    .navigationTitle("About")
            }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { DictBackdrop(scheme: scheme) }
        }
        // Switches, pickers and selections light up in the scheme's color.
        .tint(scheme.accent)
        .preferredColorScheme(.dark)
    }

    /// The sidebar's order, for the arrow keys.
    static let order: [MainSection] = [.history, .general, .replacements, .license, .about]

    static func step(_ section: MainSection, by offset: Int) -> MainSection {
        let index = order.firstIndex(of: section) ?? 0
        return order[min(max(index + offset, 0), order.count - 1)]
    }
}

/// A sidebar entry drawn by hand, because the system sidebar always paints
/// its icons and selection in the Mac's accent color, not the scheme's.
private struct SidebarRow: View {
    var title: String
    var systemImage: String
    var section: MainSection
    @Bindable var model: MainWindowModel
    var scheme: HUDColorScheme

    private var isSelected: Bool { model.section == section }

    var body: some View {
        Button {
            model.section = section
        } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(scheme.accent)
                    .frame(width: 20)
                Text(title)
                    .foregroundStyle(isSelected ? scheme.text : .primary)
                    .fontWeight(isSelected ? .semibold : .regular)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(LinearGradient(colors: [scheme.pillTop, scheme.pillBottom], startPoint: .top, endPoint: .bottom))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(scheme.glow.opacity(0.45), lineWidth: 1)
                        }
                        .shadow(color: scheme.glow.opacity(0.2), radius: 6)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 1, leading: 4, bottom: 1, trailing: 4))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
                            .listRowBackground(Color.clear)
                    }
                }
                .dictBackdrop(settings.hudColorScheme)
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
