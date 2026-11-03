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
