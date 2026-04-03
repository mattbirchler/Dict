import AppKit
import SwiftUI

final class HUDPanelController {
    private var panel: NSPanel?
    private var hudState = HUDState()

    func show(audioLevel: @escaping () -> Float, micName: @escaping () -> String) {
        hudState.mode = .recording
        hudState.audioLevel = audioLevel
        hudState.micName = micName

        guard panel == nil else { return }

        let hostingView = NSHostingView(rootView:
            WaveformHUDContainer(state: hudState)
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 56)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 56),
            styleMask: [.nonactivatingPanel, .hudWindow, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = hostingView
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 160
            let y = screenFrame.minY + 80
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        self.panel = panel
    }

    func showProcessing() {
        hudState.mode = .processing
    }

    func dismiss() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            panel.orderOut(nil)
            self?.panel = nil
        })
    }
}

@Observable
final class HUDState {
    var mode: HUDMode = .recording
    var audioLevel: (() -> Float)?
    var micName: (() -> String)?
}

struct WaveformHUDContainer: View {
    var state: HUDState

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05)) { timeline in
            WaveformHUD(
                mode: state.mode,
                audioLevel: state.audioLevel?() ?? 0,
                micName: state.micName?() ?? "",
                pulsePhase: timeline.date.timeIntervalSinceReferenceDate
            )
        }
    }
}
