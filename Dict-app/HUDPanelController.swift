import AppKit
import SwiftUI

final class HUDPanelController {
    /// Transparent canvas the capsule animates within. Larger than the
    /// capsule so spring overshoot, width changes, and the shadow are never
    /// clipped, and fixed so mode changes animate in SwiftUI instead of
    /// resizing the window. Sized for the expanded hands-free panel.
    private static let canvasSize = CGSize(width: 560, height: 240)
    /// Gap between the capsule's bottom edge and the visible screen bottom.
    private static let bottomInset: CGFloat = 80
    /// How long the success checkmark stays up before the HUD leaves.
    private static let successHold: Duration = .milliseconds(550)
    /// How long a notice ("Nothing heard", "Loading speech model") stays up.
    private static let noticeHold: Duration = .milliseconds(1400)

    /// Off only for `--preview-hud`, where the HUD should stay up.
    var autoDismiss = true
    private var panel: NSPanel?
    /// For `--preview-hud --snapshot`: the panel's window number once shown.
    var windowNumber: Int? { panel?.windowNumber }
    private let hudState = HUDState()
    private var pendingDismiss: Task<Void, Never>?
    /// Bumped on every show/dismiss so a finished exit animation can tell
    /// whether the HUD was re-shown while it ran.
    private var presentation = 0

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Colors the HUD lights up in; set from Settings.
    var colorScheme: HUDColorScheme {
        get { hudState.colorScheme }
        set { hudState.colorScheme = newValue }
    }

    func show(
        audioSpectrum: @escaping () -> [Float],
        micName: @escaping () -> String,
        liveTranscript: @escaping () -> LiveTranscript,
        hotkeyGlyph: String
    ) {
        pendingDismiss?.cancel()
        presentation += 1
        hudState.audioSpectrum = audioSpectrum
        hudState.micName = micName
        hudState.liveTranscript = liveTranscript
        hudState.hotkeyGlyph = hotkeyGlyph
        hudState.reduceMotion = reduceMotion

        present(mode: .recording)
    }

    /// Shows a short notice in place of a recording, for a hotkey press
    /// that can't start one, then leaves on its own.
    func showNotice(_ message: String) {
        pendingDismiss?.cancel()
        presentation += 1
        hudState.reduceMotion = reduceMotion
        present(mode: .failed(message: message))
        guard autoDismiss else { return }
        pendingDismiss = Task { [weak self] in
            try? await Task.sleep(for: Self.noticeHold)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    /// Brings the panel up in `mode`, morphing if it's already on screen.
    private func present(mode: HUDMode) {
        let panel = self.panel ?? makePanel()
        position(panel)
        panel.orderFrontRegardless()

        if hudState.isPresented {
            // Re-shown mid-exit or right after a success: morph.
            withAnimation(HUDAnimation.morph(reduceMotion)) {
                hudState.mode = mode
                hudState.showsLiveTranscript = false
            }
        } else {
            hudState.mode = mode
            hudState.showsLiveTranscript = false
            withAnimation(HUDAnimation.entrance(reduceMotion)) { hudState.isPresented = true }
        }
    }

    /// Hands-free: with a live preview the pill grows into a panel that
    /// shows the transcript as it forms.
    func showHandsFree(livePreview: Bool) {
        withAnimation(HUDAnimation.morph(reduceMotion)) {
            hudState.mode = .recordingHandsFree
            hudState.showsLiveTranscript = livePreview
        }
    }

    /// Grows the recording pill into the panel that shows words as they
    /// are recognized, without leaving hold-to-talk.
    func showLiveWords() {
        guard hudState.isPresented, hudState.mode == .recording else { return }
        withAnimation(HUDAnimation.morph(reduceMotion)) {
            hudState.showsLiveTranscript = true
        }
    }

    func showProcessing() {
        withAnimation(HUDAnimation.morph(reduceMotion)) {
            hudState.mode = .processing
            hudState.showsLiveTranscript = false
        }
    }

    /// Ends a dictation: a brief checkmark when text went in, a short
    /// notice when nothing did, and a plain exit when it was cancelled.
    func finish(result: DictationResult) {
        guard hudState.isPresented else {
            dismiss()
            return
        }
        let mode: HUDMode
        let hold: Duration
        switch result {
        case .inserted:
            mode = .done
            hold = Self.successHold
        case .nothingHeard, .failed:
            mode = .failed(message: result.hudMessage ?? "")
            hold = Self.noticeHold
        case .cancelled:
            dismiss()
            return
        }
        withAnimation(HUDAnimation.morph(reduceMotion)) { hudState.mode = mode }
        guard autoDismiss else { return }
        pendingDismiss = Task { [weak self] in
            try? await Task.sleep(for: hold)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        pendingDismiss?.cancel()
        guard let panel, hudState.isPresented else { return }
        presentation += 1
        let dismissal = presentation
        withAnimation(HUDAnimation.exit(reduceMotion)) {
            hudState.isPresented = false
        } completion: { [weak self] in
            guard let self, self.presentation == dismissal else { return }
            panel.orderOut(nil)
        }
    }

    private func makePanel() -> NSPanel {
        let hostingView = NSHostingView(rootView: WaveformHUDContainer(state: hudState))

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.canvasSize),
            styleMask: [.nonactivatingPanel, .hudWindow, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        // The HUD is always dark, whatever the system appearance: white
        // text and a lit waveform stay readable over any wallpaper, which
        // the light glass material could not promise.
        panel.appearance = NSAppearance(named: .darkAqua)
        // The window shadow would trace the whole canvas mid-animation; the
        // capsule draws its own.
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.contentView = hostingView
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Render the empty (not presented) state once so the first show
        // animates the insertion instead of appearing fully formed.
        hostingView.layoutSubtreeIfNeeded()

        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel) {
        let screens = NSScreen.screens
        guard let index = HUDScreenPicker.pick(
            screens: screens.map(\.frame),
            focusedWindow: HUDScreenPicker.focusedWindowFrame(),
            mouse: NSEvent.mouseLocation
        ) else { return }
        let screenFrame = screens[index].visibleFrame
        let origin = NSPoint(
            x: screenFrame.midX - Self.canvasSize.width / 2,
            y: screenFrame.minY + Self.bottomInset - WaveformHUDContainer.bottomPadding
        )
        panel.setFrame(NSRect(origin: origin, size: Self.canvasSize), display: false)
    }
}

/// The HUD's motion vocabulary. Reduce Motion swaps every spring for a
/// short fade.
enum HUDAnimation {
    static func entrance(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .spring(duration: 0.28, bounce: 0.3)
    }

    static func morph(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(duration: 0.35, bounce: 0.25)
    }

    static func exit(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeIn(duration: 0.15) : .smooth(duration: 0.22)
    }
}

@Observable
final class HUDState {
    var isPresented = false
    var mode: HUDMode = .recording
    var reduceMotion = false
    var showsLiveTranscript = false
    var hotkeyGlyph = "⌘"
    var colorScheme: HUDColorScheme = .ember
    var audioSpectrum: (() -> [Float])?
    var micName: (() -> String)?
    var liveTranscript: (() -> LiveTranscript)?
}

struct WaveformHUDContainer: View {
    /// Space below the capsule inside the canvas, for its shadow and the
    /// entrance's upward travel.
    static let bottomPadding: CGFloat = 24

    var state: HUDState

    var body: some View {
        ZStack(alignment: .bottom) {
            if state.isPresented {
                TimelineView(.animation(minimumInterval: 0.05)) { timeline in
                    WaveformHUD(
                        mode: state.mode,
                        spectrum: state.audioSpectrum?() ?? [],
                        micName: state.micName?() ?? "",
                        transcript: state.showsLiveTranscript ? (state.liveTranscript?() ?? LiveTranscript()) : nil,
                        hotkeyGlyph: state.hotkeyGlyph,
                        scheme: state.colorScheme,
                        pulsePhase: timeline.date.timeIntervalSinceReferenceDate
                    )
                }
                .transition(state.reduceMotion ? .opacity : .hudPop)
            }
        }
        .padding(.bottom, Self.bottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}

private extension AnyTransition {
    /// Springs up from below and comes into focus; on the way out it
    /// shrinks, drops, and softens.
    static var hudPop: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.75, anchor: .bottom)
                .combined(with: .offset(y: 10))
                .combined(with: .opacity)
                .combined(with: .modifier(active: HUDBlur(radius: 8), identity: HUDBlur(radius: 0))),
            removal: .scale(scale: 0.85, anchor: .bottom)
                .combined(with: .offset(y: 8))
                .combined(with: .opacity)
                .combined(with: .modifier(active: HUDBlur(radius: 4), identity: HUDBlur(radius: 0)))
        )
    }
}

private struct HUDBlur: ViewModifier {
    var radius: CGFloat

    func body(content: Content) -> some View {
        content.blur(radius: radius)
    }
}
