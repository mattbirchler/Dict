import AppKit
import SwiftUI

final class HUDPanelController {
    private var panel: NSPanel?

    func show(audioLevel: @escaping () -> Float, micName: @escaping () -> String) {
        guard panel == nil else { return }

        let hostingView = NSHostingView(rootView:
            WaveformHUDContainer(audioLevel: audioLevel, micName: micName)
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

        // Position at bottom center of main screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 160
            let y = screenFrame.minY + 80
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 1
        }

        self.panel = panel
    }

    func dismiss() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            panel.orderOut(nil)
            self?.panel = nil
        })
    }
}

struct WaveformHUDContainer: View {
    var audioLevel: () -> Float
    var micName: () -> String

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05)) { _ in
            WaveformHUD(audioLevel: audioLevel(), micName: micName())
        }
    }
}
