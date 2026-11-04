import SwiftUI
import AppKit

/// Settings > License: trial status, the Buy button, and where a key goes.
struct LicenseView: View {
    let license: LicenseStore
    var scheme: HUDColorScheme
    @State private var keyText = ""
    @State private var problem: String?
    @State private var confirmingRemove = false
    @State private var copied = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(headline)
                        .font(HUDFont.label(15, weight: .semibold))
                        .foregroundStyle(scheme.text)
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            } header: {
                DictSectionHeader("Status", scheme: scheme)
            }

            if case .licensed(let owned) = license.status {
                Section {
                    LabeledContent("Licensed to", value: owned.email)
                    LabeledContent("Purchased", value: Self.purchaseDate(owned.issued))
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Button("Copy License Key") { copy(owned.key) }
                            if copied {
                                Label("Copied", systemImage: "checkmark")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .transition(.opacity)
                            }
                        }
                        Text("Keep your key somewhere safe, like a password manager. You\u{2019}ll need it to set up Dict on another Mac.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button("Remove License from This Mac…", role: .destructive) {
                        confirmingRemove = true
                    }
                } header: {
                    DictSectionHeader("Your license", scheme: scheme)
                }
            } else {
                Section {
                    Button("Buy Dict…") { NSWorkspace.shared.open(LicenseStore.purchaseURL) }
                        .buttonStyle(.borderedProminent)
                    Text("Checkout opens in your browser. When you\u{2019}re done, click Activate on the confirmation page and Dict unlocks. One purchase covers all of your Macs.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    DictSectionHeader("Buy", scheme: scheme)
                }

                Section {
                    TextField("License key", text: $keyText, prompt: Text("DICT1-\u{2026}"), axis: .vertical)
                        .lineLimit(2...4)
                        .labelsHidden()
                        .multilineTextAlignment(.leading)
                        .font(.system(.callout, design: .monospaced))
                        .onSubmit(activate)
                    HStack {
                        Button("Activate", action: activate)
                            .disabled(keyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Spacer()
                    }
                    if let message = problem ?? license.linkProblem {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    DictSectionHeader("Enter a license key", scheme: scheme)
                }
            }
        }
        .formStyle(.grouped)
        .dictBackdrop(scheme)
        .confirmationDialog("Remove the license from this Mac?", isPresented: $confirmingRemove) {
            Button("Remove License", role: .destructive) { license.deactivate() }
        } message: {
            Text("Dict goes back to its trial state on this Mac. You can enter the same key again at any time.")
        }
    }

    private func copy(_ key: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(key, forType: .string)
        withAnimation { copied = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { copied = false }
        }
    }

    private func activate() {
        do {
            try license.activate(keyText)
            keyText = ""
            problem = nil
        } catch {
            problem = error.message
        }
    }

    private var headline: String {
        switch license.status {
        case .licensed: "Dict is licensed"
        case .trial(let days): days == 1 ? "Free trial: 1 day left" : "Free trial: \(days) days left"
        case .expired: "Your free trial has ended"
        }
    }

    private var detail: String {
        switch license.status {
        case .licensed:
            "Thanks for buying Dict. Your key was checked on this Mac, and Dict never contacts a server to confirm it."
        case .trial:
            "Everything works during the trial. When it ends, dictation stops until you enter a license key. Your settings and history stay put."
        case .expired:
            "Buy Dict to keep dictating. Your settings and history are all still here."
        }
    }

    /// "2026-11-04" as "November 4, 2026".
    static func purchaseDate(_ issued: String) -> String {
        guard let date = try? Date(issued + "T12:00:00Z", strategy: .iso8601) else { return issued }
        return date.formatted(date: .long, time: .omitted)
    }
}
