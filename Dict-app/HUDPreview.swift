import AppKit
import ScreenCaptureKit

/// Developer aid: `Dict --preview-hud recording [--appearance dark|light]
/// [--scheme ember|phosphor|glacier|ultraviolet|graphite] [--snapshot out.png]` shows the HUD with sample audio and no hotkey, so it
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

        let transcript = LiveTranscript(
            confirmed: "I think we should ship the new build tomorrow as long as we finish testing",
            tentative: "before the deadline on Friday"
        )
        if let scheme = arguments.firstIndex(of: "--scheme"), scheme + 1 < arguments.count,
           let choice = HUDColorScheme(rawValue: arguments[scheme + 1]) {
            hud.colorScheme = choice
        }
        let started = Date()
        hud.autoDismiss = false
        hud.show(
            audioSpectrum: { Self.sampleSpectrum(at: Date().timeIntervalSince(started)) },
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

    /// A speech-like spectrum: a hump of energy in the low-mid bands that
    /// pulses like syllables, with a little wobble per band.
    static func sampleSpectrum(at t: TimeInterval) -> [Float] {
        let count = SpectrumAnalyzer.bandCount
        let syllable = pow(max(0, sin(t * 7.3)), 1.6) * (0.6 + 0.4 * sin(t * 1.7))
        return (0..<count).map { band in
            let centre = exp(-pow((Double(band) - Double(count) * 0.38) / (Double(count) * 0.3), 2))
            let wobble = 0.75 + 0.25 * sin(t * 2.1 + Double(band) * 0.9)
            return Float(min(1, (0.08 + syllable * 0.95) * (0.3 + 0.9 * centre) * wobble))
        }
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
