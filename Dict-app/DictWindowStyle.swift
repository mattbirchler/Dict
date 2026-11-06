import SwiftUI

/// The main window's share of the panel's look: the scheme's gradient
/// behind every section (near-black in dark mode, a tinted paper white in
/// light), section titles in the panel's typeface, and native controls
/// tinted with the chosen color scheme.

/// The window background: the scheme's panel colors, with a faint glow at
/// the top like light catching the panel's rim.
struct DictBackdrop: View {
    var scheme: HUDColorScheme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = scheme.window(colorScheme)
        ZStack(alignment: .top) {
            LinearGradient(colors: [palette.backdropTop, palette.backdropBottom], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [palette.glow.opacity(palette.glowOpacity), .clear], center: .top, startRadius: 0, endRadius: 420)
                .frame(height: 320)
        }
        .ignoresSafeArea()
    }
}

/// A form section title: uppercase, tracked, in the scheme's accent.
struct DictSectionHeader: View {
    var title: String
    var scheme: HUDColorScheme
    @Environment(\.colorScheme) private var colorScheme

    init(_ title: String, scheme: HUDColorScheme) {
        self.title = title
        self.scheme = scheme
    }

    var body: some View {
        Text(title.uppercased())
            .font(HUDFont.label(11, weight: .semibold))
            .tracking(1.6)
            .foregroundStyle(scheme.window(colorScheme).accent.opacity(0.9))
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
    @Environment(\.colorScheme) private var colorScheme
    private let started = Date()

    var body: some View {
        let palette = scheme.hud(colorScheme)
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
                        .foregroundStyle(palette.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("\(scheme.displayName.uppercased()) SCHEME")
                        .font(HUDFont.label(10, weight: .medium))
                        .tracking(1.6)
                        .foregroundStyle(palette.accent.opacity(0.8))
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .panelSurface(palette, cornerRadius: 14)
        .shadow(color: palette.isLight ? palette.shadow.opacity(0.4) : .clear, radius: 8, y: 3)
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
