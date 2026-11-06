import SwiftUI

/// The colors the dot matrix and HUD accents are lit with. The pill itself
/// stays near-black in every scheme so the lit dots carry the look.
enum HUDColorScheme: String, CaseIterable, Identifiable {
    case ember, phosphor, glacier, ultraviolet, graphite

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ember: "Ember"
        case .phosphor: "Phosphor"
        case .glacier: "Glacier"
        case .ultraviolet: "Ultraviolet"
        case .graphite: "Graphite"
        }
    }

    /// Color of a lit dot at the bottom of a column (quiet) and the top (loud).
    var low: Color {
        switch self {
        case .ember: Color(red: 1.0, green: 0.42, blue: 0.16)
        case .phosphor: Color(red: 0.20, green: 0.85, blue: 0.45)
        case .glacier: Color(red: 0.20, green: 0.55, blue: 1.0)
        case .ultraviolet: Color(red: 0.55, green: 0.30, blue: 1.0)
        case .graphite: Color(white: 0.70)
        }
    }

    var high: Color {
        switch self {
        case .ember: Color(red: 1.0, green: 0.24, blue: 0.50)
        case .phosphor: Color(red: 0.75, green: 1.0, blue: 0.55)
        case .glacier: Color(red: 0.45, green: 0.95, blue: 1.0)
        case .ultraviolet: Color(red: 1.0, green: 0.40, blue: 0.80)
        case .graphite: Color(white: 1.0)
        }
    }

    /// The bloom around lit dots and the pill's outer glow.
    var glow: Color {
        switch self {
        case .ember: Color(red: 1.0, green: 0.35, blue: 0.25)
        case .phosphor: Color(red: 0.35, green: 1.0, blue: 0.55)
        case .glacier: Color(red: 0.30, green: 0.75, blue: 1.0)
        case .ultraviolet: Color(red: 0.75, green: 0.35, blue: 1.0)
        case .graphite: Color(white: 0.9)
        }
    }

    /// Accent for hints, the processing label and the success mark.
    var accent: Color {
        switch self {
        case .ember: Color(red: 1.0, green: 0.69, blue: 0.40)
        case .phosphor: Color(red: 0.55, green: 0.95, blue: 0.65)
        case .glacier: Color(red: 0.55, green: 0.85, blue: 1.0)
        case .ultraviolet: Color(red: 0.85, green: 0.65, blue: 1.0)
        case .graphite: Color(white: 0.85)
        }
    }

    /// Unlit dots, barely there.
    var unlit: Color { low.opacity(0.14) }

    var success: Color {
        switch self {
        case .ember: Color(red: 1.0, green: 0.82, blue: 0.40)
        default: accent
        }
    }

    /// Warm or cool near-black for the pill, leaning toward the scheme.
    var pillTop: Color {
        switch self {
        case .ember: Color(red: 0.10, green: 0.08, blue: 0.09)
        case .phosphor: Color(red: 0.07, green: 0.10, blue: 0.08)
        case .glacier: Color(red: 0.07, green: 0.09, blue: 0.12)
        case .ultraviolet: Color(red: 0.09, green: 0.07, blue: 0.12)
        case .graphite: Color(white: 0.09)
        }
    }

    var pillBottom: Color {
        switch self {
        case .ember: Color(red: 0.05, green: 0.04, blue: 0.05)
        case .phosphor: Color(red: 0.03, green: 0.05, blue: 0.04)
        case .glacier: Color(red: 0.03, green: 0.04, blue: 0.07)
        case .ultraviolet: Color(red: 0.05, green: 0.03, blue: 0.07)
        case .graphite: Color(white: 0.04)
        }
    }

    /// Status text and the transcript.
    var text: Color {
        switch self {
        case .ember: Color(red: 1.0, green: 0.95, blue: 0.90)
        case .phosphor: Color(red: 0.92, green: 1.0, blue: 0.94)
        case .glacier: Color(red: 0.92, green: 0.97, blue: 1.0)
        case .ultraviolet: Color(red: 0.96, green: 0.93, blue: 1.0)
        case .graphite: Color(white: 0.96)
        }
    }

    var recording: Color { Color(red: 1.0, green: 0.23, blue: 0.19) }
    var failure: Color { Color(red: 1.0, green: 0.62, blue: 0.20) }
}

/// Every color the dictation panel (and the panel-style cards in the main
/// window) draws with, for one scheme in one appearance. Dark is the
/// original look; light is a white panel with the dots lit in deeper,
/// saturated versions of the scheme's colors so they read on white.
struct HUDPalette {
    var low: Color
    var high: Color
    var glow: Color
    /// How strongly lit dots bloom. Softer on white, where a full glow smears.
    var bloom: Double
    var accent: Color
    var unlit: Color
    var success: Color
    var pillTop: Color
    var pillBottom: Color
    var text: Color
    var recording: Color
    var failure: Color
    /// The panel's rim, top to bottom.
    var rim: [Color]
    /// The drop shadow under the panel.
    var shadow: Color
    var isLight: Bool
}

extension HUDColorScheme {
    func hud(_ colorScheme: ColorScheme) -> HUDPalette {
        colorScheme == .light ? lightHUD : darkHUD
    }

    private var darkHUD: HUDPalette {
        HUDPalette(
            low: low, high: high, glow: glow, bloom: 0.9, accent: accent, unlit: unlit,
            success: success, pillTop: pillTop, pillBottom: pillBottom, text: text,
            recording: recording, failure: failure,
            rim: [glow.opacity(0.45), Color.white.opacity(0.06), glow.opacity(0.12)],
            shadow: .black.opacity(0.5),
            isLight: false
        )
    }

    private var lightHUD: HUDPalette {
        let low: Color, high: Color, accent: Color, text: Color, top: Color, bottom: Color
        switch self {
        case .ember:
            low = Color(red: 0.96, green: 0.36, blue: 0.06); high = Color(red: 0.88, green: 0.10, blue: 0.38)
            accent = Color(red: 0.78, green: 0.30, blue: 0.06); text = Color(red: 0.18, green: 0.09, blue: 0.05)
            top = Color(red: 1.0, green: 0.992, blue: 0.985); bottom = Color(red: 0.975, green: 0.950, blue: 0.935)
        case .phosphor:
            low = Color(red: 0.05, green: 0.62, blue: 0.30); high = Color(red: 0.30, green: 0.72, blue: 0.05)
            accent = Color(red: 0.07, green: 0.50, blue: 0.24); text = Color(red: 0.05, green: 0.15, blue: 0.09)
            top = Color(red: 0.990, green: 1.0, blue: 0.992); bottom = Color(red: 0.935, green: 0.970, blue: 0.945)
        case .glacier:
            low = Color(red: 0.10, green: 0.42, blue: 0.95); high = Color(red: 0.0, green: 0.68, blue: 0.88)
            accent = Color(red: 0.05, green: 0.40, blue: 0.80); text = Color(red: 0.05, green: 0.10, blue: 0.20)
            top = Color(red: 0.990, green: 0.995, blue: 1.0); bottom = Color(red: 0.935, green: 0.955, blue: 0.985)
        case .ultraviolet:
            low = Color(red: 0.46, green: 0.22, blue: 0.96); high = Color(red: 0.88, green: 0.18, blue: 0.64)
            accent = Color(red: 0.45, green: 0.22, blue: 0.84); text = Color(red: 0.13, green: 0.07, blue: 0.22)
            top = Color(red: 0.995, green: 0.990, blue: 1.0); bottom = Color(red: 0.952, green: 0.938, blue: 0.985)
        case .graphite:
            // Inverted: quiet is a light grey, loud is near-black ink.
            low = Color(white: 0.58); high = Color(white: 0.10)
            accent = Color(white: 0.30); text = Color(white: 0.10)
            top = Color(white: 0.995); bottom = Color(white: 0.945)
        }
        return HUDPalette(
            low: low, high: high, glow: low, bloom: 0.45, accent: accent,
            unlit: text.opacity(0.09),
            success: self == .ember ? Color(red: 0.80, green: 0.50, blue: 0.0) : accent,
            pillTop: top, pillBottom: bottom, text: text,
            recording: Color(red: 0.90, green: 0.14, blue: 0.12),
            failure: Color(red: 0.84, green: 0.42, blue: 0.0),
            rim: [Color.white, text.opacity(0.10), text.opacity(0.16)],
            shadow: .black.opacity(0.18),
            isLight: true
        )
    }
}

extension View {
    /// The panel's body: the palette's gradient, a lit rim and a glow, in a
    /// rounded rectangle. Used by the floating panel and its copies in the
    /// main window.
    func panelSurface(_ palette: HUDPalette, cornerRadius: CGFloat, glow: Double = 0.14, glowRadius: CGFloat = 16) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(LinearGradient(colors: [palette.pillTop, palette.pillBottom], startPoint: .top, endPoint: .bottom))
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(LinearGradient(colors: palette.rim, startPoint: .top, endPoint: .bottom), lineWidth: 1)
        }
        .shadow(color: palette.glow.opacity(palette.isLight ? glow * 0.6 : glow), radius: glowRadius)
    }
}
