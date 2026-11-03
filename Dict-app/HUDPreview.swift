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
        case "livewords": hud.showLiveWords()
        case "processing": hud.showProcessing()
        case "done": hud.finish(result: .inserted("preview"))
        case "failed": hud.finish(result: .nothingHeard)
        default: break
        }

        scheduleSnapshot(from: arguments) { hud.windowNumber }
        return true
    }

    /// `Dict --preview-window general|about|history [--snapshot out.png]`:
    /// opens the main window on that section for a look at Settings.
    @MainActor
    static func presentWindow(from arguments: [String] = CommandLine.arguments, show: (MainSection) -> Int?) -> Bool {
        guard let flag = arguments.firstIndex(of: "--preview-window"), flag + 1 < arguments.count else { return false }
        let section: MainSection
        switch arguments[flag + 1] {
        case "about": section = .about
        case "history": section = .history
        case "replacements": section = .replacements
        default: section = .general
        }
        let number = show(section)
        scheduleSnapshot(from: arguments) { number }
        return true
    }

    /// `Dict --preview-onboarding welcome|listen|accessibility|key|tryit|accuracy|done [--snapshot out.png]`.
    @MainActor
    static func presentOnboarding(from arguments: [String] = CommandLine.arguments, show: (OnboardingStep) -> Int?) -> Bool {
        guard let flag = arguments.firstIndex(of: "--preview-onboarding"), flag + 1 < arguments.count else { return false }
        let step: OnboardingStep
        switch arguments[flag + 1] {
        case "listen": step = .listen
        case "accessibility": step = .accessibility
        case "key": step = .chooseKey
        case "tryit": step = .tryIt
        case "accuracy": step = .accuracy
        case "done": step = .done
        default: step = .welcome
        }
        let number = show(step)
        scheduleSnapshot(from: arguments) { number }
        return true
    }

    /// With --snapshot, writes a PNG of the window after its entrance
    /// animation, then quits.
    @MainActor
    private static func scheduleSnapshot(from arguments: [String], windowNumber: @escaping @MainActor () -> Int?) {
        guard let snapshot = arguments.firstIndex(of: "--snapshot"), snapshot + 1 < arguments.count else { return }
        let path = arguments[snapshot + 1]
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            if let number = windowNumber() {
                await write(windowNumber: number, to: path)
            }
            NSApp.terminate(nil)
        }
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
