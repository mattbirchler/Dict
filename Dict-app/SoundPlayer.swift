import AppKit

/// The three short sounds that mark a dictation: start, stop, inserted.
/// Bundled as WAV in Resources; quiet by design, and off with one toggle.
enum AppSound: String, CaseIterable {
    case start = "dict-start"
    case stop = "dict-stop"
    case inserted = "dict-inserted"
}

@MainActor
enum SoundPlayer {
    /// Set from Settings; nothing plays while false.
    static var isEnabled = true
    /// Off for `--preview-*` runs and tests.
    static var isMuted = false

    private static var cache: [AppSound: NSSound] = [:]

    static func play(_ sound: AppSound) {
        guard isEnabled, !isMuted else { return }
        let player: NSSound
        if let cached = cache[sound] {
            player = cached
        } else {
            guard let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "wav"),
                  let loaded = NSSound(contentsOf: url, byReference: true) else { return }
            loaded.volume = 0.6
            cache[sound] = loaded
            player = loaded
        }
        if player.isPlaying { player.stop() }
        player.play()
    }
}
