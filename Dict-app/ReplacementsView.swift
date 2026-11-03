import SwiftUI

/// Edits the user's word replacements: words or phrases the engine keeps
/// mishearing, and what to insert instead.
struct ReplacementsView: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                if settings.wordReplacements.isEmpty {
                    Text("No replacements yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach($settings.wordReplacements) { $rule in
                    HStack {
                        TextField("Heard as", text: $rule.spoken)
                            .labelsHidden()
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.secondary)
                        TextField("Replace with", text: $rule.replacement)
                            .labelsHidden()
                        Button {
                            settings.wordReplacements.removeAll { $0.id == rule.id }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove this replacement")
                    }
                }
                Button("Add Replacement") {
                    settings.wordReplacements.append(WordReplacement(spoken: "", replacement: ""))
                }
            } header: {
                DictSectionHeader("Replacements", scheme: settings.hudColorScheme)
            } footer: {
                Text("Fix names and jargon that get transcribed wrong, like \u{201C}clod code\u{201D} \u{2192} \u{201C}Claude Code.\u{201D} Matches whole words and ignores capitalization. Applied to every dictation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .dictBackdrop(settings.hudColorScheme)
    }
}
