import SwiftUI

enum HUDMode: Equatable {
    case recording
    case recordingHandsFree
    case processing
    /// Brief success state shown after the text is inserted.
    case done
    /// Brief notice when a dictation produced nothing, or couldn't start.
    case failed(message: String)
    /// Brief notice that the speech model finished loading.
    case ready
}

/// Chakra Petch, bundled with the app, for the HUD's labels. Falls back to
/// the system font if the bundle is missing it (unit tests).
enum HUDFont {
    static func label(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        let name = weight == .bold ? "ChakraPetch-Bold" : (weight == .medium ? "ChakraPetch-Medium" : "ChakraPetch-SemiBold")
        return .custom(name, size: size)
    }
}

/// The dictation pill: a dot-matrix spectrum that lights up as you speak,
/// a blinking record LED and uppercase labels, on a near-black panel. The
/// lit colors come from the user's `HUDColorScheme`.
struct WaveformHUD: View {
    var mode: HUDMode
    /// Band levels (0...1), low to high frequency, for the matrix.
    var spectrum: [Float]
    var micName: String
    /// False while the mic is still opening, so the label can say so
    /// instead of looking like a recording that hears nothing.
    var isListening = true
    /// Non-nil while the expanded hands-free panel is showing.
    var transcript: LiveTranscript? = nil
    var hotkeyGlyph = "⌘"
    var scheme: HUDColorScheme = .ember
    var pulsePhase: Double = 0

    static let expandedWidth: CGFloat = 530
    /// The pill's matrix is the menu bar glyph's scale: half the full grid.
    static let matrixScale: CGFloat = 0.5

    private var isRecording: Bool { mode == .recording || mode == .recordingHandsFree }
    private var isExpanded: Bool { transcript != nil }
    private var cornerRadius: CGFloat { isExpanded ? 20 : 14 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
                .frame(minHeight: DotMatrix.height * Self.matrixScale)
            if let transcript {
                LiveTranscriptText(transcript: transcript, scheme: scheme)
                    .transition(.opacity.combined(with: .offset(y: -6)))
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 15)
        .padding(.vertical, 9)
        .frame(width: isExpanded ? Self.expandedWidth : nil, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(LinearGradient(colors: [scheme.pillTop, scheme.pillBottom], startPoint: .top, endPoint: .bottom))
        }
        .overlay {
            // Lit rim: brightest along the top edge, like light catching a bezel.
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [scheme.glow.opacity(0.45), Color.white.opacity(0.06), scheme.glow.opacity(0.12)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: .black.opacity(0.5), radius: 16, y: 8)
        .shadow(color: scheme.glow.opacity(isRecording ? 0.16 : 0.08), radius: 20)
        // New transcript lines grow the panel smoothly instead of snapping.
        .animation(.smooth(duration: 0.25), value: transcript)
    }

    private var header: some View {
        HStack(spacing: 10) {
            if isRecording {
                RecordLED(pulsePhase: pulsePhase, color: scheme.recording)
                    .transition(.scale.combined(with: .opacity))
            } else if mode == .done || mode == .ready {
                StatusGlyph(systemName: "checkmark", color: scheme.success)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
            } else if case .failed = mode {
                StatusGlyph(systemName: "exclamationmark", color: scheme.failure)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
            }

            if isRecording || mode == .processing {
                DotMatrix(spectrum: spectrum, isLive: isRecording, scheme: scheme, phase: pulsePhase, scale: Self.matrixScale)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }

            Text(statusText)
                .font(HUDFont.label(10))
                .tracking(1)
                .foregroundStyle(statusColor)
                .lineLimit(1)
                .fixedSize()
                .contentTransition(.interpolate)

            if let hint = hintText {
                if isExpanded { Spacer(minLength: 12) }
                Text(hint)
                    .font(HUDFont.label(8.5, weight: .medium))
                    .tracking(1.2)
                    .foregroundStyle(scheme.accent.opacity(0.8))
                    .fixedSize()
                    .transition(.opacity)
            }
        }
    }

    private var statusText: String {
        switch mode {
        case .recording: return isListening ? micName.uppercased() : "CONNECTING \(micName.uppercased())"
        case .recordingHandsFree: return "HANDS-FREE"
        case .processing: return "PROCESSING"
        case .done: return "INSERTED"
        case .ready: return "READY TO DICTATE"
        case .failed(let message): return message.uppercased()
        }
    }

    private var statusColor: Color {
        switch mode {
        case .processing: scheme.accent
        case .done, .ready: scheme.success
        case .recording where !isListening: scheme.text.opacity(0.55)
        default: scheme.text
        }
    }

    private var hintText: String? {
        switch mode {
        case .recordingHandsFree: "\(hotkeyGlyph.uppercased()) FINISH · ESC CANCEL"
        case .processing: "ESC CANCEL"
        case .ready: "HOLD \(hotkeyGlyph.uppercased())"
        default: nil
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
    var scheme: HUDColorScheme
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
                .foregroundStyle(scheme.text.opacity(0.5))
        } else {
            let confirmed = Text(transcript.confirmed).foregroundStyle(scheme.text)
            let separator = transcript.confirmed.isEmpty || transcript.tentative.isEmpty ? "" : " "
            let tentative = Text(separator + transcript.tentative).foregroundStyle(scheme.text.opacity(0.5))
            Text("\(confirmed)\(tentative)")
        }
    }
}

/// Record LED: a small red dot that blinks slowly and glows.
private struct RecordLED: View {
    var pulsePhase: Double
    var color: Color

    var body: some View {
        // Slow blink: fully lit most of the time, dipping once a second.
        let blink = 0.5 + 0.5 * cos(pulsePhase * 2 * .pi * 0.9)
        let lit = 0.45 + 0.55 * blink
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .opacity(lit)
            .shadow(color: color.opacity(0.9 * lit), radius: 5)
            .frame(width: 11, height: 11)
    }
}

/// The checkmark or warning glyph, lit from behind.
private struct StatusGlyph: View {
    var systemName: String
    var color: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 11, weight: .heavy))
            .foregroundStyle(color)
            .shadow(color: color.opacity(0.9), radius: 5)
            .frame(width: 11, height: 11)
    }
}

/// A grid of LEDs. Each column is one frequency band, low on the left;
/// dots light from the bottom up with the band's level, graded from the
/// scheme's low color to its high color, and the topmost lit dot of each
/// column hangs for a beat before falling, like a VU meter's peak bar.
/// While processing, a dim wave travels across the grid instead.
struct DotMatrix: View {
    static let columns = SpectrumAnalyzer.bandCount
    static let rows = 6
    static let pitch: CGFloat = 7
    static let dot: CGFloat = 4.4
    static var width: CGFloat { CGFloat(columns) * pitch }
    static var height: CGFloat { CGFloat(rows) * pitch }

    var spectrum: [Float]
    var isLive: Bool
    var scheme: HUDColorScheme
    var phase: Double
    /// Shrinks pitch, dots and bloom together; 1 is the full-size grid.
    var scale: CGFloat = 1

    @State private var peaks = [Double](repeating: 0, count: DotMatrix.columns)
    @State private var smoothed = [Double](repeating: 0, count: DotMatrix.columns)

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            Self.draw(
                in: &context,
                size: size,
                // Before the first reading has been smoothed in (a still
                // render, say), draw the incoming levels as they are.
                levels: isLive ? (smoothed.allSatisfy { $0 == 0 } ? spectrum.map(Double.init) : smoothed) : Self.idleLevels(phase: phase),
                peaks: isLive ? peaks : [],
                scheme: scheme,
                scale: scale
            )
        }
        .frame(width: Self.width * scale, height: Self.height * scale)
        .onChange(of: spectrum, initial: true) { _, new in
            Self.step(levels: &smoothed, peaks: &peaks, incoming: new)
        }
        .onChange(of: phase) { _, _ in
            // Levels arrive every ~85 ms; between arrivals let peaks sink.
            if isLive { Self.decayPeaks(&peaks, floor: smoothed) }
        }
    }

    /// Blends a new reading toward the displayed levels (fast attack, slower
    /// release) and lifts peaks to any new maximum.
    static func step(levels: inout [Double], peaks: inout [Double], incoming: [Float]) {
        for column in 0..<columns {
            let target = column < incoming.count ? Double(incoming[column]) : 0
            let current = levels[column]
            levels[column] = target > current ? current + (target - current) * 0.8 : current + (target - current) * 0.45
            if levels[column] > peaks[column] { peaks[column] = levels[column] }
        }
    }

    static func decayPeaks(_ peaks: inout [Double], floor: [Double]) {
        for column in 0..<columns {
            peaks[column] = max(floor[column], peaks[column] - 0.035)
        }
    }

    /// A low wave that drifts across the grid while the transcript is decoded.
    static func idleLevels(phase: Double) -> [Double] {
        (0..<columns).map { column in
            let wave = (sin(phase * 4 - Double(column) * 0.55) + 1) / 2
            return 0.12 + 0.22 * wave
        }
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, levels: [Double], peaks: [Double], scheme: HUDColorScheme, scale: CGFloat = 1) {
        let lowColor = scheme.low, highColor = scheme.high
        let pitch = Self.pitch * scale, dot = Self.dot * scale
        var lit: [(CGRect, Color)] = []
        for column in 0..<columns {
            let level = column < levels.count ? levels[column] : 0
            let litRows = Int((level * Double(rows)).rounded())
            let peak = column < peaks.count ? Int((peaks[column] * Double(rows)).rounded()) : 0
            for row in 0..<rows {
                // Row 0 is the bottom of the column.
                let fromBottom = row + 1
                let isLit = fromBottom <= litRows
                let isPeak = fromBottom == peak && peak > litRows
                let x = CGFloat(column) * pitch + (pitch - dot) / 2
                let y = size.height - CGFloat(fromBottom) * pitch + (pitch - dot) / 2
                let rect = CGRect(x: x, y: y, width: dot, height: dot)
                if isLit || isPeak {
                    let fraction = Double(row) / Double(max(rows - 1, 1))
                    lit.append((isPeak ? rect.insetBy(dx: -0.5 * scale, dy: -0.5 * scale) : rect, Self.mix(lowColor, highColor, fraction)))
                } else {
                    context.fill(Circle().path(in: rect), with: .color(scheme.unlit))
                }
            }
        }
        // Lit dots bloom; unlit ones stay flat.
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: scheme.glow.opacity(0.9), radius: 3.5 * scale))
            for (rect, color) in lit {
                layer.fill(Circle().path(in: rect), with: .color(color))
            }
        }
    }

    /// Linear blend between two colors in sRGB.
    static func mix(_ a: Color, _ b: Color, _ t: Double) -> Color {
        let ra = a.resolve(in: .init()), rb = b.resolve(in: .init())
        let f = Float(min(max(t, 0), 1))
        return Color(
            red: Double(ra.red + (rb.red - ra.red) * f),
            green: Double(ra.green + (rb.green - ra.green) * f),
            blue: Double(ra.blue + (rb.blue - ra.blue) * f)
        )
    }
}
