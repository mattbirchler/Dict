import SwiftUI

/// Four lifetime numbers on the HUD's panel, at the top of History.
struct StatsHeader: View {
    var stats: DictationStats
    var scheme: HUDColorScheme

    var body: some View {
        HStack(spacing: 0) {
            tile(value: Self.compact(stats.words), label: "Words")
            divider
            tile(value: Self.compact(stats.dictations), label: "Dictations")
            divider
            tile(value: Self.duration(stats.secondsSaved), label: "Time saved")
            divider
            tile(value: "\(stats.streak())", label: stats.streak() == 1 ? "Day streak" : "Day streak")
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [scheme.pillTop, scheme.pillBottom], startPoint: .top, endPoint: .bottom))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [scheme.glow.opacity(0.4), Color.white.opacity(0.05), scheme.glow.opacity(0.1)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
        }
        .shadow(color: scheme.glow.opacity(0.12), radius: 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(stats.words) words dictated, \(stats.dictations) dictations, \(Self.duration(stats.secondsSaved)) saved, \(stats.streak()) day streak")
    }

    private func tile(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(HUDFont.label(24, weight: .bold))
                .foregroundStyle(scheme.high)
                .shadow(color: scheme.glow.opacity(0.6), radius: 6)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label.uppercased())
                .font(HUDFont.label(10, weight: .medium))
                .tracking(1.6)
                .foregroundStyle(scheme.accent.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 1, height: 36)
    }

    /// 1,234 up to 9,999, then 12.3K, 1.2M.
    static func compact(_ n: Int) -> String {
        switch n {
        case ..<10_000: return n.formatted(.number.grouping(.automatic))
        case ..<1_000_000: return String(format: "%.1fK", Double(n) / 1_000).replacingOccurrences(of: ".0K", with: "K")
        default: return String(format: "%.1fM", Double(n) / 1_000_000).replacingOccurrences(of: ".0M", with: "M")
        }
    }

    /// "0 min", "45 min", "3.5 h", "12 h".
    static func duration(_ seconds: Double) -> String {
        let minutes = seconds / 60
        if minutes < 60 { return "\(Int(minutes.rounded())) min" }
        let hours = minutes / 60
        return hours < 10 ? String(format: "%.1f h", hours).replacingOccurrences(of: ".0 h", with: " h") : "\(Int(hours.rounded())) h"
    }
}
