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
    /// Non-nil while the expanded hands-free panel is showing.
    var transcript: LiveTranscript? = nil
    var hotkeyGlyph = "⌘"
    var pulsePhase: Double = 0

    static let expandedWidth: CGFloat = 460

    private var isRecording: Bool { mode == .recording || mode == .recordingHandsFree }
    private var isExpanded: Bool { transcript != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
                .frame(minHeight: LevelBars.maxHeight)
            if let transcript {
                LiveTranscriptText(transcript: transcript)
                    .transition(.opacity.combined(with: .offset(y: -6)))
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, 22)
        .padding(.vertical, 12)
        .frame(width: isExpanded ? Self.expandedWidth : nil, alignment: .leading)
        // A rounded rect whose radius is half the compact height draws the
        // capsule, so the pill-to-panel morph animates one continuous shape.
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: isExpanded ? 20 : 24, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        // New transcript lines grow the panel smoothly instead of snapping.
        .animation(.smooth(duration: 0.25), value: transcript)
    }

    private var header: some View {
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

            if isExpanded {
                Spacer(minLength: 12)
                Text("\(hotkeyGlyph) to finish · esc to cancel")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .fixedSize()
                    .transition(.opacity)
            }
        }
    }

    private var statusText: String {
        switch mode {
        case .recording: return micName
        case .recordingHandsFree:
            return isExpanded ? "Hands-free" : "Hands-free — \(hotkeyGlyph) to finish, esc to cancel"
        case .processing: return "Processing — esc to cancel"
        case .done: return "Inserted"
        }
    }
}

/// The transcript so far: settled words in full color, the newest words
/// (which may still change) dimmer. Shows the latest few lines; once the
/// text outgrows them, older lines scroll up and fade out at the top.
private struct LiveTranscriptText: View {
    /// Four lines of 14 pt text plus part of a fifth, so once the text
    /// overflows, a half-visible line fades out at the top and reads as
    /// scrolled away rather than as tentative words.
    static let maxHeight: CGFloat = 88

    var transcript: LiveTranscript
    @State private var isOverflowing = false

    var body: some View {
        content
            .font(.system(size: 14))
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                isOverflowing = height > Self.maxHeight
            }
            .frame(maxWidth: .infinity, maxHeight: Self.maxHeight, alignment: .bottomLeading)
            .clipped()
            .mask {
                if isOverflowing {
                    LinearGradient(
                        stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.22)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                } else {
                    Color.black
                }
            }
    }

    @ViewBuilder private var content: some View {
        if transcript.isEmpty {
            Text("Listening…")
                .foregroundStyle(.tertiary)
        } else {
            let confirmed = Text(transcript.confirmed).foregroundStyle(.primary)
            let separator = transcript.confirmed.isEmpty || transcript.tentative.isEmpty ? "" : " "
            let tentative = Text(separator + transcript.tentative).foregroundStyle(.secondary)
            Text("\(confirmed)\(tentative)")
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
