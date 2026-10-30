import AppKit
import SwiftUI

final class HUDPanelController {
    /// Transparent canvas the capsule animates within. Larger than the
    /// capsule so spring overshoot, width changes, and the shadow are never
    /// clipped, and fixed so mode changes animate in SwiftUI instead of
    /// resizing the window.
    private static let canvasSize = CGSize(width: 440, height: 120)
    /// Gap between the capsule's bottom edge and the visible screen bottom.
    private static let bottomInset: CGFloat = 80
    /// How long the success checkmark stays up before the HUD leaves.
    private static let successHold: Duration = .milliseconds(550)

    private var panel: NSPanel?
    private let hudState = HUDState()
    private var pendingDismiss: Task<Void, Never>?
    /// Bumped on every show/dismiss so a finished exit animation can tell
    /// whether the HUD was re-shown while it ran.
    private var presentation = 0

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    func show(audioLevels: @escaping () -> [Float], micName: @escaping () -> String) {
        pendingDismiss?.cancel()
        presentation += 1
        hudState.audioLevels = audioLevels
        hudState.micName = micName
        hudState.reduceMotion = reduceMotion

        let panel = self.panel ?? makePanel()
        position(panel)
        panel.orderFrontRegardless()

        if hudState.isPresented {
            // Re-shown mid-exit or right after a success: morph back.
            withAnimation(HUDAnimation.morph(reduceMotion)) { hudState.mode = .recording }
        } else {
            hudState.mode = .recording
            withAnimation(HUDAnimation.entrance(reduceMotion)) { hudState.isPresented = true }
        }
    }

    func showHandsFree() {
        withAnimation(HUDAnimation.morph(reduceMotion)) { hudState.mode = .recordingHandsFree }
    }

    func showProcessing() {
        withAnimation(HUDAnimation.morph(reduceMotion)) { hudState.mode = .processing }
    }

    /// Ends a processed dictation: a brief checkmark on success, then exit.
    func finish(success: Bool) {
        guard success, hudState.isPresented else {
            dismiss()
            return
        }
        withAnimation(HUDAnimation.morph(reduceMotion)) { hudState.mode = .done }
        pendingDismiss = Task { [weak self] in
            try? await Task.sleep(for: Self.successHold)
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
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
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
    var audioLevels: (() -> [Float])?
    var micName: (() -> String)?
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
                        levels: state.audioLevels?() ?? [],
                        micName: state.micName?() ?? "",
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
