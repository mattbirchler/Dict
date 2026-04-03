import SwiftUI

struct WaveformHUD: View {
    var audioLevel: Float
    var micName: String

    private let barCount = 7
    private let barWidth: CGFloat = 3
    private let maxBarHeight: CGFloat = 24
    private let minBarHeight: CGFloat = 4

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05)) { timeline in
            let pulse = (sin(timeline.date.timeIntervalSinceReferenceDate * 4) + 1) / 2

            HStack(spacing: 14) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
                    .shadow(color: .red.opacity(0.6), radius: 4)
                    .opacity(0.4 + pulse * 0.6)

                HStack(spacing: 3) {
                    ForEach(0..<barCount, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.green.opacity(0.85))
                            .frame(width: barWidth, height: barHeight(for: index))
                    }
                }
                .frame(height: maxBarHeight)
                .animation(.easeInOut(duration: 0.15), value: audioLevel)

                Text(micName)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: Capsule())
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let position = Double(index) / Double(barCount - 1)
        let wave = sin(position * .pi)
        let level = CGFloat(audioLevel)
        let height = minBarHeight + (maxBarHeight - minBarHeight) * level * wave
        return max(minBarHeight, height)
    }
}
