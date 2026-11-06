import SwiftUI

/// Settings control for the HUD color scheme: one small live pill per
/// scheme, each lit by the same sample speech so they can be compared.
struct HUDSchemePicker: View {
    @Binding var selection: HUDColorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private let started = Date()

    var body: some View {
        TimelineView(.periodic(from: .now, by: reduceMotion ? 3600 : 0.085)) { timeline in
            let spectrum = HUDPreview.sampleSpectrum(at: timeline.date.timeIntervalSince(started))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 86, maximum: 120), spacing: 8)], spacing: 8) {
                ForEach(HUDColorScheme.allCases) { scheme in
                    SchemeTile(
                        scheme: scheme,
                        spectrum: spectrum,
                        phase: timeline.date.timeIntervalSinceReferenceDate,
                        isSelected: scheme == selection,
                        selectionColor: selection.window(colorScheme).accent
                    )
                    .onTapGesture { selection = scheme }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(scheme.displayName)
                    .accessibilityAddTraits(scheme == selection ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
    }
}

private struct SchemeTile: View {
    var scheme: HUDColorScheme
    var spectrum: [Float]
    var phase: Double
    var isSelected: Bool
    var selectionColor: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = scheme.hud(colorScheme)
        VStack(spacing: 6) {
            DotMatrix(spectrum: spectrum, isLive: true, scheme: scheme, phase: phase)
                .scaleEffect(0.55)
                .frame(width: DotMatrix.width * 0.55, height: DotMatrix.height * 0.55)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .panelSurface(palette, cornerRadius: 10, glow: 0, glowRadius: 0)
            Text(scheme.displayName)
                .font(.caption)
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .padding(6)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? selectionColor.opacity(0.12) : .clear)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? selectionColor : .clear, lineWidth: 2)
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}
