import SwiftUI

enum HUDMode {
    case recording
    case recordingHandsFree
    case processing
}

struct WaveformHUD: View {
    var mode: HUDMode
    var audioLevel: Float
    var micName: String
    var pulsePhase: Double = 0

    private let barCount = 7
    private let barWidth: CGFloat = 3
    private let maxBarHeight: CGFloat = 24
    private let minBarHeight: CGFloat = 4

    private var isRecording: Bool { mode == .recording || mode == .recordingHandsFree }

    var body: some View {
        let pulse = (sin(pulsePhase * 4) + 1) / 2

        HStack(spacing: 14) {
            ZStack {
                // Recording indicator
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
                    .shadow(color: .red.opacity(0.6), radius: 4)
                    .opacity(isRecording ? (0.4 + pulse * 0.6) : 0)

                // Processing spinner
                ProgressView()
                    .controlSize(.small)
                    .opacity(isRecording ? 0 : 1)
            }

            if isRecording {
                HStack(spacing: 3) {
                    ForEach(0..<barCount, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.green.opacity(0.85))
                            .frame(width: barWidth, height: barHeight(for: index))
                    }
                }
                .frame(height: maxBarHeight)
                .animation(.easeInOut(duration: 0.15), value: audioLevel)
            }

            Text(statusText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var statusText: String {
        switch mode {
        case .recording: return micName
        case .recordingHandsFree: return "Hands-free — press ⌘ to stop"
        case .processing: return "Processing…"
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
