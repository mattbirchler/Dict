import Foundation

enum HotkeyChoice: String, CaseIterable {
    case rightCommand, rightControl, rightOption, fn

    var displayName: String {
        switch self {
        case .rightCommand: "Right Command (⌘)"
        case .rightControl: "Right Control (⌃)"
        case .rightOption: "Right Option (⌥)"
        case .fn: "Fn / Globe (🌐)"
        }
    }
}

enum ActivationMode: String, CaseIterable {
    case holdToTalk, toggle

    var displayName: String {
        switch self {
        case .holdToTalk: "Press and hold"
        case .toggle: "Press to start and stop"
        }
    }
}

enum HistoryLimit: String, CaseIterable {
    case off, ten, fifty, twoHundred, unlimited

    /// Maximum stored entries; nil means unlimited.
    var maxEntries: Int? {
        switch self {
        case .off: 0
        case .ten: 10
        case .fifty: 50
        case .twoHundred: 200
        case .unlimited: nil
        }
    }

    var savesHistory: Bool { self != .off }

    var displayName: String {
        switch self {
        case .off: "Off"
        case .ten: "Last 10"
        case .fifty: "Last 50"
        case .twoHundred: "Last 200"
        case .unlimited: "Unlimited"
        }
    }
}

enum TranscriptionEngineChoice: String, CaseIterable {
    case apple, parakeet, whisper

    var displayName: String {
        switch self {
        case .apple: "Apple"
        case .parakeet: "Parakeet"
        case .whisper: "Whisper"
        }
    }

    /// One-line tradeoff shown in onboarding / settings.
    var blurb: String {
        switch self {
        case .apple: "Fast, already on your Mac. No download."
        case .parakeet: "Most accurate, near-instant results. ~500 MB download."
        case .whisper: "Accurate but slower. ~1 GB download."
        }
    }

    /// Name of the engine's model shown in the onboarding readiness row.
    var modelDisplayName: String {
        switch self {
        case .apple: "Apple Speech"
        case .parakeet: "Parakeet Model"
        case .whisper: "Whisper Model"
        }
    }

    /// Label for the explicit download step; nil when the engine has none.
    var downloadPrompt: String? {
        switch self {
        case .apple: nil
        case .parakeet: "Download Parakeet model (~500 MB)"
        case .whisper: "Download Whisper model (~1 GB)"
        }
    }
}

/// Owns every persisted preference. Each property writes UserDefaults on set
/// and fires `onChange` so non-SwiftUI services (KeyMonitor, HistoryStore,
/// PipelineCoordinator) can be reconfigured; SwiftUI observes directly.
@MainActor
@Observable
final class SettingsStore {
    enum Change { case hotkey, activationMode, formatting, historyLimit, transcriptionEngine, appendTrailingSpace, smartLeadingSpace, wordReplacements }

    @ObservationIgnored var onChange: ((Change) -> Void)?
    @ObservationIgnored private let defaults: UserDefaults

    private enum Keys {
        static let hotkey = "hotkey"
        static let activationMode = "activationMode"
        // Pre-existing key from earlier builds — do not rename.
        static let isFormattingEnabled = "isFormattingEnabled"
        static let historyLimit = "historyLimit"
        static let transcriptionEngine = "transcriptionEngine"
        static let appendTrailingSpace = "appendTrailingSpace"
        static let smartLeadingSpace = "smartLeadingSpace"
        static let wordReplacements = "wordReplacements"
    }

    var hotkey: HotkeyChoice {
        didSet {
            defaults.set(hotkey.rawValue, forKey: Keys.hotkey)
            onChange?(.hotkey)
        }
    }

    var activationMode: ActivationMode {
        didSet {
            defaults.set(activationMode.rawValue, forKey: Keys.activationMode)
            onChange?(.activationMode)
        }
    }

    var isFormattingEnabled: Bool {
        didSet {
            defaults.set(isFormattingEnabled, forKey: Keys.isFormattingEnabled)
            onChange?(.formatting)
        }
    }

    var historyLimit: HistoryLimit {
        didSet {
            defaults.set(historyLimit.rawValue, forKey: Keys.historyLimit)
            onChange?(.historyLimit)
        }
    }

    var transcriptionEngine: TranscriptionEngineChoice {
        didSet {
            defaults.set(transcriptionEngine.rawValue, forKey: Keys.transcriptionEngine)
            onChange?(.transcriptionEngine)
        }
    }

    var appendTrailingSpace: Bool {
        didSet {
            defaults.set(appendTrailingSpace, forKey: Keys.appendTrailingSpace)
            onChange?(.appendTrailingSpace)
        }
    }

    var smartLeadingSpace: Bool {
        didSet {
            defaults.set(smartLeadingSpace, forKey: Keys.smartLeadingSpace)
            onChange?(.smartLeadingSpace)
        }
    }

    /// Stored as JSON; rules with an empty spoken phrase are kept so a row
    /// being edited in the UI doesn't vanish, and skipped when applied.
    var wordReplacements: [WordReplacement] {
        didSet {
            if let data = try? JSONEncoder().encode(wordReplacements) {
                defaults.set(data, forKey: Keys.wordReplacements)
            }
            onChange?(.wordReplacements)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hotkey = defaults.string(forKey: Keys.hotkey)
            .flatMap(HotkeyChoice.init(rawValue:)) ?? .rightCommand
        self.activationMode = defaults.string(forKey: Keys.activationMode)
            .flatMap(ActivationMode.init(rawValue:)) ?? .holdToTalk
        self.isFormattingEnabled = defaults.object(forKey: Keys.isFormattingEnabled) as? Bool ?? true
        self.historyLimit = defaults.string(forKey: Keys.historyLimit)
            .flatMap(HistoryLimit.init(rawValue:)) ?? .fifty
        if let raw = defaults.string(forKey: Keys.transcriptionEngine),
           let choice = TranscriptionEngineChoice(rawValue: raw) {
            self.transcriptionEngine = choice
        } else if defaults.bool(forKey: "hasCompletedOnboarding") {
            // Existing user upgrading: keep Whisper so nothing changes for them.
            self.transcriptionEngine = .whisper
        } else {
            // Fresh install: default to Apple (no 1 GB download to get started).
            self.transcriptionEngine = .apple
        }
        self.appendTrailingSpace = defaults.object(forKey: Keys.appendTrailingSpace) as? Bool ?? false
        self.smartLeadingSpace = defaults.object(forKey: Keys.smartLeadingSpace) as? Bool ?? true
        self.wordReplacements = defaults.data(forKey: Keys.wordReplacements)
            .flatMap { try? JSONDecoder().decode([WordReplacement].self, from: $0) } ?? []
    }
}
