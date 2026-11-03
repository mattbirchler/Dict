import SwiftUI

/// The main window's share of the panel's look: the panel's near-black
/// gradient behind every section, section titles in the panel's typeface,
/// and native controls tinted with the chosen color scheme.

/// The window background: the scheme's panel colors, with a faint glow at
/// the top like light catching the panel's rim.
struct DictBackdrop: View {
    var scheme: HUDColorScheme

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [scheme.pillTop, scheme.pillBottom], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [scheme.glow.opacity(0.10), .clear], center: .top, startRadius: 0, endRadius: 420)
                .frame(height: 320)
        }
        .ignoresSafeArea()
    }
}

/// A form section title: uppercase, tracked, in the scheme's accent.
struct DictSectionHeader: View {
    var title: String
    var scheme: HUDColorScheme

    init(_ title: String, scheme: HUDColorScheme) {
        self.title = title
        self.scheme = scheme
    }

    var body: some View {
        Text(title.uppercased())
            .font(HUDFont.label(11, weight: .semibold))
            .tracking(1.6)
            .foregroundStyle(scheme.accent.opacity(0.9))
            .accessibilityAddTraits(.isHeader)
    }
}

extension View {
    /// Puts a grouped form or list on the panel backdrop.
    func dictBackdrop(_ scheme: HUDColorScheme) -> some View {
        scrollContentBackground(.hidden)
            .background { DictBackdrop(scheme: scheme) }
    }
}

/// The card at the top of General: a live grid in the current scheme and
/// how to start dictating, so a scheme change shows up right away.
struct SettingsHero: View {
    var scheme: HUDColorScheme
    var hotkey: HotkeyChoice
    var mode: ActivationMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let started = Date()

    var body: some View {
        TimelineView(.periodic(from: .now, by: reduceMotion ? 3600 : 0.085)) { timeline in
            HStack(spacing: 18) {
                DotMatrix(
                    spectrum: HUDPreview.sampleSpectrum(at: timeline.date.timeIntervalSince(started)),
                    isLive: true,
                    scheme: scheme,
                    phase: timeline.date.timeIntervalSinceReferenceDate
                )
                VStack(alignment: .leading, spacing: 6) {
                    Text(instruction.uppercased())
                        .font(HUDFont.label(15, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(scheme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("\(scheme.displayName.uppercased()) SCHEME")
                        .font(HUDFont.label(10, weight: .medium))
                        .tracking(1.6)
                        .foregroundStyle(scheme.accent.opacity(0.8))
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [scheme.pillTop, scheme.pillBottom], startPoint: .top, endPoint: .bottom))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [scheme.glow.opacity(0.45), Color.white.opacity(0.06), scheme.glow.opacity(0.12)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
        }
        .shadow(color: scheme.glow.opacity(0.14), radius: 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(instruction)
    }

    private var instruction: String {
        switch mode {
        case .holdToTalk: "Hold \(hotkey.glyph) to dictate"
        case .toggle: "Press \(hotkey.glyph) to dictate"
        }
    }
}
