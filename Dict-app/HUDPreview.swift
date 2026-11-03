import AppKit
import ScreenCaptureKit

/// Developer aid: `Dict --preview-hud recording [--appearance dark|light]
/// [--snapshot out.png]` shows the HUD with sample audio and no hotkey, so it
/// can be looked at and screenshotted. With --snapshot it writes a PNG of
/// the panel after the entrance animation and quits. Modes: recording,
/// handsfree, processing, done, failed. Nothing else in the app starts.
enum HUDPreview {
    @MainActor
    static func present(from arguments: [String] = CommandLine.arguments, in hud: HUDPanelController) -> Bool {
        guard let flag = arguments.firstIndex(of: "--preview-hud"), flag + 1 < arguments.count else { return false }
        if let appearance = arguments.firstIndex(of: "--appearance"), appearance + 1 < arguments.count {
            NSApp.appearance = NSAppearance(named: arguments[appearance + 1] == "light" ? .aqua : .darkAqua)
        }

        let levels: [Float] = (0..<64).map { index -> Float in
            let t = Double(index)
            let envelope: Double = abs(sin(t * 0.7)) * abs(cos(t * 0.23))
            return Float(0.1 + 0.55 * envelope)
        }
        let transcript = LiveTranscript(
            confirmed: "I think we should ship the new build tomorrow as long as we finish testing",
            tentative: "before the deadline on Friday"
        )
        hud.autoDismiss = false
        hud.show(
            audioLevels: { levels },
            micName: { "MacBook Pro Microphone" },
            liveTranscript: { transcript },
            hotkeyGlyph: "⌘"
        )
        switch arguments[flag + 1] {
        case "handsfree": hud.showHandsFree(livePreview: true)
        case "processing": hud.showProcessing()
        case "done": hud.finish(result: .inserted("preview"))
        case "failed": hud.finish(result: .nothingHeard)
        default: break
        }

        if let snapshot = arguments.firstIndex(of: "--snapshot"), snapshot + 1 < arguments.count {
            let path = arguments[snapshot + 1]
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5))
                if let number = hud.windowNumber {
                    await write(windowNumber: number, to: path)
                }
                NSApp.terminate(nil)
            }
        }
        return true
    }

    /// Captures the panel's pixels with ScreenCaptureKit and writes a PNG.
    private static func write(windowNumber: Int, to path: String) async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let window = content.windows.first(where: { $0.windowID == CGWindowID(windowNumber) }) else {
                FileHandle.standardError.write(Data("snapshot: HUD window not found\n".utf8)); return
            }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            let scale = NSScreen.main?.backingScaleFactor ?? 2
            config.width = Int(window.frame.width * scale)
            config.height = Int(window.frame.height * scale)
            config.showsCursor = false
            config.captureResolution = .best
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let rep = NSBitmapImageRep(cgImage: image)
            guard let png = rep.representation(using: .png, properties: [:]) else { return }
            try png.write(to: URL(fileURLWithPath: path))
        } catch {
            FileHandle.standardError.write(Data("snapshot failed: \(error)\n".utf8))
        }
    }
}
