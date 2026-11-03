import SwiftUI

enum HUDMode: Equatable {
    case recording
    case recordingHandsFree
    case processing
    /// Brief success state shown after the text is inserted.
    case done
    /// Brief notice when a dictation produced nothing, or couldn't start.
    case failed(message: String)
}

/// The HUD's colors. The waveform and glows carry one accent gradient over
/// dark tinted glass. The panel forces the dark appearance, so the light
/// values are only a fallback for previews that override it.
struct HUDPalette {
    let colorScheme: ColorScheme

    /// Left-to-right gradient across the waveform.
    var wave: LinearGradient {
        LinearGradient(colors: waveColors, startPoint: .leading, endPoint: .trailing)
    }

    var waveColors: [Color] {
        switch colorScheme {
        case .dark: [Color(red: 0.35, green: 0.55, blue: 1.0), Color(red: 0.45, green: 0.95, blue: 1.0)]
        default: [Color(red: 0.05, green: 0.30, blue: 0.95), Color(red: 0.0, green: 0.62, blue: 0.85)]
        }
    }

    /// Glow behind the live waveform.
    var waveGlow: Color {
        colorScheme == .dark ? Color(red: 0.4, green: 0.8, blue: 1.0) : Color(red: 0.1, green: 0.45, blue: 1.0)
    }

    var glassTint: Color {
        colorScheme == .dark ? Color(white: 0.05).opacity(0.7) : Color.white.opacity(0.45)
    }

    /// Hairline along the pill's edge, brightest at the top like a lit rim.
    var rim: LinearGradient {
        let top = colorScheme == .dark ? Color.white.opacity(0.35) : Color.white.opacity(0.9)
        let bottom = colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.08)
        return LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
    }

    var success: Color { Color(red: 0.25, green: 0.85, blue: 0.5) }
    var failure: Color { Color(red: 1.0, green: 0.62, blue: 0.2) }
    var recording: Color { Color(red: 1.0, green: 0.3, blue: 0.3) }
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

    @Environment(\.colorScheme) private var colorScheme

    static let expandedWidth: CGFloat = 460

    private var palette: HUDPalette { HUDPalette(colorScheme: colorScheme) }
    private var isRecording: Bool { mode == .recording || mode == .recordingHandsFree }
    private var isExpanded: Bool { transcript != nil }
    private var cornerRadius: CGFloat { isExpanded ? 22 : 26 }

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
        .padding(.vertical, 13)
        .frame(width: isExpanded ? Self.expandedWidth : nil, alignment: .leading)
        // A rounded rect whose radius is half the compact height draws the
        // capsule, so the pill-to-panel morph animates one continuous shape.
        .glassEffect(.regular.tint(palette.glassTint), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(palette.rim, lineWidth: 1)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.45 : 0.22), radius: 16, y: 6)
        // New transcript lines grow the panel smoothly instead of snapping.
        .animation(.smooth(duration: 0.25), value: transcript)
    }

    private var header: some View {
        HStack(spacing: 12) {
            if isRecording {
                RecordingDot(pulsePhase: pulsePhase, color: palette.recording)
                    .transition(.scale.combined(with: .opacity))
            } else if mode == .done {
                StatusGlyph(systemName: "checkmark.circle.fill", color: palette.success)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
            } else if case .failed = mode {
                StatusGlyph(systemName: "exclamationmark.circle.fill", color: palette.failure)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
            }

            if isRecording || mode == .processing {
                LevelBars(
                    heights: isRecording
                        ? LevelBars.recordingHeights(levels: levels)
                        : LevelBars.processingHeights(phase: pulsePhase),
                    isLive: isRecording,
                    palette: palette
                )
                .transition(.scale(scale: 0.4).combined(with: .opacity))
            }

            Text(statusText)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .fixedSize()
                .contentTransition(.interpolate)

            if isExpanded {
                Spacer(minLength: 12)
                Text("\(hotkeyGlyph) to finish · esc to cancel")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .transition(.opacity)
            }
        }
    }

    private var statusText: String {
        switch mode {
        case .recording: return micName
        case .recordingHandsFree:
            return isExpanded ? "Hands-free" : "Hands-free: \(hotkeyGlyph) to finish, esc to cancel"
        case .processing: return "Processing: esc to cancel"
        case .done: return "Inserted"
        case .failed(let message): return message
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
                .foregroundStyle(.secondary)
        } else {
            let confirmed = Text(transcript.confirmed).foregroundStyle(.primary)
            let separator = transcript.confirmed.isEmpty || transcript.tentative.isEmpty ? "" : " "
            let tentative = Text(separator + transcript.tentative).foregroundStyle(.secondary)
            Text("\(confirmed)\(tentative)")
        }
    }
}

/// Recording dot with a glow and a halo that breathes.
private struct RecordingDot: View {
    var pulsePhase: Double
    var color: Color

    var body: some View {
        let pulse = (sin(pulsePhase * 3) + 1) / 2
        ZStack {
            Circle()
                .fill(color.opacity(0.3))
                .frame(width: 18, height: 18)
                .scaleEffect(0.6 + pulse * 0.4)
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
                .shadow(color: color.opacity(0.9), radius: 4 + pulse * 3)
        }
        .frame(width: 18, height: 18)
    }
}

/// The checkmark or warning glyph, lit from behind.
private struct StatusGlyph: View {
    var systemName: String
    var color: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(color)
            .shadow(color: color.opacity(0.8), radius: 6)
    }
}

/// A row of thin, vertically centered capsules. While recording, each bar
/// is one recent moment of audio, newest on the right; older audio fades
/// toward the left edge. While processing, the same bars carry a gentle
/// travelling wave.
private struct LevelBars: View {
    static let barCount = 24
    static let barWidth: CGFloat = 3
    static let spacing: CGFloat = 2.5
    static let maxHeight: CGFloat = 26
    static let minHeight: CGFloat = 3.5

    var heights: [CGFloat]
    var isLive: Bool
    var palette: HUDPalette

    var body: some View {
        HStack(spacing: Self.spacing) {
            ForEach(0..<Self.barCount, id: \.self) { index in
                Capsule()
                    .frame(width: Self.barWidth, height: heights[index])
            }
        }
        .frame(height: Self.maxHeight)
        .foregroundStyle(palette.wave)
        .opacity(isLive ? 1 : 0.75)
        .mask {
            LinearGradient(
                stops: [.init(color: .black.opacity(0.4), location: 0), .init(color: .black, location: 0.4)],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        .shadow(color: palette.waveGlow.opacity(isLive ? 0.7 : 0), radius: 5)
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
