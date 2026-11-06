import AppKit
import SwiftUI

/// Whether the main window and the dictation panel are dark, light, or
/// follow the Mac. Dark is the default. Onboarding stays dark.
enum AppAppearance: String, CaseIterable, Identifiable {
    case dark, light, system

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dark: "Dark"
        case .light: "Light"
        case .system: "Match System"
        }
    }

    /// nil lets the window follow the system setting.
    var nsAppearance: NSAppearance? {
        switch self {
        case .dark: NSAppearance(named: .darkAqua)
        case .light: NSAppearance(named: .aqua)
        case .system: nil
        }
    }
}

/// The colors a window's own chrome uses (backdrop, section titles, sidebar,
/// links, control tint) for one scheme in one appearance. Panel-style cards
/// use `HUDPalette` instead.
struct WindowPalette {
    var backdropTop: Color
    var backdropBottom: Color
    var glow: Color
    var glowOpacity: Double
    /// Section titles, sidebar icons, links, switches.
    var accent: Color
    var text: Color
    /// The selected sidebar row.
    var selectionFill: AnyShapeStyle
    var selectionStroke: Color
    var selectionShadow: Color
}

extension HUDColorScheme {
    func window(_ colorScheme: ColorScheme) -> WindowPalette {
        if colorScheme == .dark {
            return WindowPalette(
                backdropTop: pillTop,
                backdropBottom: pillBottom,
                glow: glow,
                glowOpacity: 0.10,
                accent: accent,
                text: text,
                selectionFill: AnyShapeStyle(LinearGradient(colors: [pillTop, pillBottom], startPoint: .top, endPoint: .bottom)),
                selectionStroke: glow.opacity(0.45),
                selectionShadow: glow.opacity(0.2)
            )
        }
        let accent = lightAccent
        return WindowPalette(
            backdropTop: lightBackdropTop,
            backdropBottom: lightBackdropBottom,
            glow: glow,
            glowOpacity: 0.16,
            accent: accent,
            text: lightText,
            selectionFill: AnyShapeStyle(accent.opacity(0.13)),
            selectionStroke: accent.opacity(0.35),
            selectionShadow: .clear
        )
    }

    /// A paper white with a hint of the scheme's hue.
    private var lightBackdropTop: Color {
        switch self {
        case .ember: Color(red: 0.995, green: 0.975, blue: 0.960)
        case .phosphor: Color(red: 0.965, green: 0.990, blue: 0.970)
        case .glacier: Color(red: 0.965, green: 0.980, blue: 1.0)
        case .ultraviolet: Color(red: 0.980, green: 0.970, blue: 1.0)
        case .graphite: Color(white: 0.975)
        }
    }

    private var lightBackdropBottom: Color {
        switch self {
        case .ember: Color(red: 0.960, green: 0.930, blue: 0.910)
        case .phosphor: Color(red: 0.915, green: 0.955, blue: 0.925)
        case .glacier: Color(red: 0.915, green: 0.940, blue: 0.975)
        case .ultraviolet: Color(red: 0.940, green: 0.920, blue: 0.975)
        case .graphite: Color(white: 0.925)
        }
    }

    /// The scheme's hue, deepened enough to read as text on white.
    private var lightAccent: Color {
        switch self {
        case .ember: Color(red: 0.80, green: 0.30, blue: 0.06)
        case .phosphor: Color(red: 0.07, green: 0.50, blue: 0.24)
        case .glacier: Color(red: 0.05, green: 0.40, blue: 0.80)
        case .ultraviolet: Color(red: 0.45, green: 0.22, blue: 0.84)
        case .graphite: Color(white: 0.30)
        }
    }

    private var lightText: Color {
        switch self {
        case .ember: Color(red: 0.18, green: 0.09, blue: 0.05)
        case .phosphor: Color(red: 0.05, green: 0.15, blue: 0.09)
        case .glacier: Color(red: 0.05, green: 0.10, blue: 0.20)
        case .ultraviolet: Color(red: 0.13, green: 0.07, blue: 0.22)
        case .graphite: Color(white: 0.10)
        }
    }
}

/// Keeps the hosting NSWindow's appearance in step with the setting, so the
/// title bar, sidebar material and native controls all switch too.
struct WindowAppearanceSetter: NSViewRepresentable {
    var appearance: AppAppearance

    func makeNSView(context: Context) -> SetterView { SetterView() }

    func updateNSView(_ view: SetterView, context: Context) {
        view.choice = appearance
    }

    final class SetterView: NSView {
        var choice: AppAppearance = .dark {
            didSet { apply() }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        private func apply() {
            guard let window else { return }
            let target = choice.nsAppearance
            if window.appearance?.name != target?.name {
                window.appearance = target
            }
        }
    }
}
