import SwiftUI

enum HUDMode {
    case recording
    case recordingHandsFree
    case processing
    /// Brief success state shown after the text is inserted.
    case done
}

struct WaveformHUD: View {
    var mode: HUDMode
    /// Recent audio levels (0...1), oldest first.
    var levels: [Float]
    var micName: String
    var pulsePhase: Double = 0

    private var isRecording: Bool { mode == .recording || mode == .recordingHandsFree }

    var body: some View {
        HStack(spacing: 12) {
            if isRecording {
                RecordingDot(pulsePhase: pulsePhase)
                    .transition(.scale.combined(with: .opacity))
            } else if mode == .done {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.green)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
            }

            if mode != .done {
                LevelBars(
                    heights: isRecording
                        ? LevelBars.recordingHeights(levels: levels)
                        : LevelBars.processingHeights(phase: pulsePhase),
                    isLive: isRecording
                )
                .transition(.scale(scale: 0.4).combined(with: .opacity))
            }

            Text(statusText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
                .contentTransition(.interpolate)
        }
        .padding(.leading, 18)
        .padding(.trailing, 22)
        .padding(.vertical, 12)
        .frame(minHeight: LevelBars.maxHeight + 24)
        .glassEffect(.regular, in: .capsule)
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
    }

    private var statusText: String {
        switch mode {
        case .recording: return micName
        case .recordingHandsFree: return "Hands-free — ⌘ to finish, esc to cancel"
        case .processing: return "Processing — esc to cancel"
        case .done: return "Inserted"
        }
    }
}

/// Red recording dot with a soft halo that breathes.
private struct RecordingDot: View {
    var pulsePhase: Double

    var body: some View {
        let pulse = (sin(pulsePhase * 3) + 1) / 2
        ZStack {
            Circle()
                .fill(Color.red.opacity(0.25))
                .frame(width: 16, height: 16)
                .scaleEffect(0.7 + pulse * 0.3)
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
        }
        .frame(width: 16, height: 16)
    }
}

/// A row of thin, vertically centered capsules. While recording, each bar
/// is one recent moment of audio, newest on the right; older audio fades
/// toward the left edge. While processing, the same bars carry a gentle
/// travelling wave.
private struct LevelBars: View {
    static let barCount = 24
    static let barWidth: CGFloat = 2.5
    static let spacing: CGFloat = 2
    static let maxHeight: CGFloat = 24
    static let minHeight: CGFloat = 3

    var heights: [CGFloat]
    var isLive: Bool

    var body: some View {
        HStack(spacing: Self.spacing) {
            ForEach(0..<Self.barCount, id: \.self) { index in
                Capsule()
                    .frame(width: Self.barWidth, height: heights[index])
            }
        }
        .frame(height: Self.maxHeight)
        .foregroundStyle(isLive ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .mask {
            LinearGradient(
                stops: [.init(color: .black.opacity(0.35), location: 0), .init(color: .black, location: 0.35)],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        // Levels arrive roughly every 85 ms; easing each bar toward its
        // new height smooths the steps without lagging behind speech.
        .animation(.easeOut(duration: 0.12), value: heights)
    }

    /// The newest `barCount` levels mapped to bar heights, left-padded with
    /// silence until enough history has arrived.
    static func recordingHeights(levels: [Float]) -> [CGFloat] {
        let recent = levels.suffix(barCount)
        let padded = [Float](repeating: 0, count: barCount - recent.count) + recent
        return padded.map { level in
            // Gain plus pow < 1 lifts quiet speech so capture reads at a glance.
            let boosted = max(0, min(level * 1.6, 1))
            let shaped = CGFloat(pow(boosted, 0.45))
            return minHeight + (maxHeight - minHeight) * shaped
        }
    }

    /// A low, slow wave travelling left to right across the bars.
    static func processingHeights(phase: Double) -> [CGFloat] {
        (0..<barCount).map { index in
            let wave = (sin(phase * 5 - Double(index) * 0.45) + 1) / 2
            return minHeight + (maxHeight * 0.45 - minHeight) * CGFloat(wave)
        }
    }
}
