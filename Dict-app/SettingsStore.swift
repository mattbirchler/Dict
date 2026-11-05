import Foundation

enum HotkeyChoice: Hashable {
    case rightCommand, rightControl, rightOption, fn
    /// Any non-modifier key plus modifiers, recorded by the user. `modifiers`
    /// is CGEventFlags masked to command, option, control and shift; `label`
    /// is the key's name as shown when it was recorded ("Space", "F18", "D").
    case custom(keycode: Int64, modifiers: UInt64, label: String)

    /// The modifier-only choices offered as quick picks.
    static let presets: [HotkeyChoice] = [.rightCommand, .rightControl, .rightOption, .fn]

    /// Modifier bits that take part in matching a custom combo.
    static let modifierMask: UInt64 = (1 << 20) | (1 << 19) | (1 << 18) | (1 << 17)

    var isCustom: Bool {
        if case .custom = self { return true }
        return false
    }

    var displayName: String {
        switch self {
        case .rightCommand: "Right Command (⌘)"
        case .rightControl: "Right Control (⌃)"
        case .rightOption: "Right Option (⌥)"
        case .fn: "Fn / Globe (🌐)"
        case .custom: glyph
        }
    }

    /// Short key symbol for on-screen hints.
    var glyph: String {
        switch self {
        case .rightCommand: "⌘"
        case .rightControl: "⌃"
        case .rightOption: "⌥"
        case .fn: "fn"
        case .custom(_, let modifiers, let label): Self.modifierGlyphs(modifiers) + label
        }
    }

    /// "⌃⌥⇧⌘" in the order macOS shows them, for whichever bits are set.
    static func modifierGlyphs(_ modifiers: UInt64) -> String {
        var out = ""
        if modifiers & (1 << 18) != 0 { out += "⌃" }
        if modifiers & (1 << 19) != 0 { out += "⌥" }
        if modifiers & (1 << 17) != 0 { out += "⇧" }
        if modifiers & (1 << 20) != 0 { out += "⌘" }
        return out
    }

    // MARK: Storage

    /// Stable string for UserDefaults; presets keep their old names so
    /// existing installs read back unchanged.
    var storageKey: String {
        switch self {
        case .rightCommand: "rightCommand"
        case .rightControl: "rightControl"
        case .rightOption: "rightOption"
        case .fn: "fn"
        case .custom(let keycode, let modifiers, let label): "custom:\(keycode):\(modifiers):\(label)"
        }
    }

    init?(storageKey: String) {
        switch storageKey {
        case "rightCommand": self = .rightCommand
        case "rightControl": self = .rightControl
        case "rightOption": self = .rightOption
        case "fn": self = .fn
        default:
            let parts = storageKey.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false)
            guard parts.count == 4, parts[0] == "custom",
                  let keycode = Int64(parts[1]), let modifiers = UInt64(parts[2]), !parts[3].isEmpty else { return nil }
            self = .custom(keycode: keycode, modifiers: modifiers, label: String(parts[3]))
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
    case apple, parakeet

    var displayName: String {
        switch self {
        case .apple: "Apple"
        case .parakeet: "Parakeet"
        }
    }

    /// One-line tradeoff shown in onboarding / settings.
    var blurb: String {
        switch self {
        case .apple: "Fast, already on your Mac. No download."
        case .parakeet: "Most accurate, near-instant results. ~500 MB download."
        }
    }

    /// Name of the engine's model shown in the onboarding readiness row.
    var modelDisplayName: String {
        switch self {
        case .apple: "Apple Speech"
        case .parakeet: "Parakeet Model"
        }
    }

    /// Apple's SpeechAnalyzer sits behind the system Speech Recognition
    /// permission; Parakeet runs its own model and never needs it.
    var needsSpeechRecognitionPermission: Bool {
        switch self {
        case .apple: true
        case .parakeet: false
        }
    }

    /// Label for the explicit download step; nil when the engine has none.
    var downloadPrompt: String? {
        switch self {
        case .apple: nil
        case .parakeet: "Download Parakeet model (~500 MB)"
        }
    }
}

/// Owns every persisted preference. Each property writes UserDefaults on set
/// and fires `onChange` so non-SwiftUI services (KeyMonitor, HistoryStore,
/// PipelineCoordinator) can be reconfigured; SwiftUI observes directly.
@MainActor
@Observable
final class SettingsStore {
    enum Change { case hotkey, activationMode, formatting, historyLimit, transcriptionEngine, appendTrailingSpace, smartLeadingSpace, wordReplacements, inputDevice, hudColorScheme, sounds, dictationStyle, screenContext, liveWords, usageData }

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
        static let inputDevice = "inputDevice"
        static let hudColorScheme = "hudColorScheme"
        static let playsSounds = "playsSounds"
        static let dictationStyle = "dictationStyle"
        static let usesScreenContext = "usesScreenContext"
        static let showsLiveWords = "showsLiveWords"
        static let insertsLiveWords = "insertsLiveWords"
        static let sharesUsageData = "sharesUsageData"
    }

    var hotkey: HotkeyChoice {
        didSet {
            defaults.set(hotkey.storageKey, forKey: Keys.hotkey)
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

    /// Which microphone to record from; stored as JSON.
    var inputDevice: InputDeviceChoice {
        didSet {
            if let data = try? JSONEncoder().encode(inputDevice) {
                defaults.set(data, forKey: Keys.inputDevice)
            }
            onChange?(.inputDevice)
        }
    }

    /// Colors the HUD lights up in.
    var hudColorScheme: HUDColorScheme {
        didSet {
            defaults.set(hudColorScheme.rawValue, forKey: Keys.hudColorScheme)
            onChange?(.hudColorScheme)
        }
    }

    /// Short sounds at the start and end of a dictation.
    var playsSounds: Bool {
        didSet {
            defaults.set(playsSounds, forKey: Keys.playsSounds)
            onChange?(.sounds)
        }
    }

    /// How much the formatter may change what was said.
    var dictationStyle: DictationStyle {
        didSet {
            defaults.set(dictationStyle.rawValue, forKey: Keys.dictationStyle)
            onChange?(.dictationStyle)
        }
    }

    /// Read the field being dictated into so names are spelled its way.
    var usesScreenContext: Bool {
        didSet {
            defaults.set(usesScreenContext, forKey: Keys.usesScreenContext)
            onChange?(.screenContext)
        }
    }

    /// Show the words in the panel while the key is held, not only hands-free.
    var showsLiveWords: Bool {
        didSet {
            defaults.set(showsLiveWords, forKey: Keys.showsLiveWords)
            onChange?(.liveWords)
        }
    }

    /// Type words into the focused field as they are recognized.
    var insertsLiveWords: Bool {
        didSet {
            defaults.set(insertsLiveWords, forKey: Keys.insertsLiveWords)
            onChange?(.liveWords)
        }
    }

    /// Send anonymous usage counts (see Analytics). On unless turned off.
    var sharesUsageData: Bool {
        didSet {
            defaults.set(sharesUsageData, forKey: Keys.sharesUsageData)
            onChange?(.usageData)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.sharesUsageData = defaults.object(forKey: Keys.sharesUsageData) as? Bool ?? true
        self.showsLiveWords = defaults.object(forKey: Keys.showsLiveWords) as? Bool ?? false
        self.insertsLiveWords = defaults.object(forKey: Keys.insertsLiveWords) as? Bool ?? false
        self.usesScreenContext = defaults.object(forKey: Keys.usesScreenContext) as? Bool ?? true
        self.dictationStyle = defaults.string(forKey: Keys.dictationStyle)
            .flatMap(DictationStyle.init(rawValue:)) ?? .verbatim
        self.playsSounds = defaults.object(forKey: Keys.playsSounds) as? Bool ?? true
        self.hudColorScheme = defaults.string(forKey: Keys.hudColorScheme)
            .flatMap(HUDColorScheme.init(rawValue:)) ?? .ember
        self.inputDevice = defaults.data(forKey: Keys.inputDevice)
            .flatMap { try? JSONDecoder().decode(InputDeviceChoice.self, from: $0) } ?? .automatic
        self.hotkey = defaults.string(forKey: Keys.hotkey)
            .flatMap(HotkeyChoice.init(storageKey:)) ?? .rightCommand
        self.activationMode = defaults.string(forKey: Keys.activationMode)
            .flatMap(ActivationMode.init(rawValue:)) ?? .holdToTalk
        self.isFormattingEnabled = defaults.object(forKey: Keys.isFormattingEnabled) as? Bool ?? true
        self.historyLimit = defaults.string(forKey: Keys.historyLimit)
            .flatMap(HistoryLimit.init(rawValue:)) ?? .fifty
        // Unknown values (including "whisper" from pre-1.0 builds) fall back
        // to Apple, which needs no download.
        self.transcriptionEngine = defaults.string(forKey: Keys.transcriptionEngine)
            .flatMap(TranscriptionEngineChoice.init(rawValue:)) ?? .apple
        self.appendTrailingSpace = defaults.object(forKey: Keys.appendTrailingSpace) as? Bool ?? false
        self.smartLeadingSpace = defaults.object(forKey: Keys.smartLeadingSpace) as? Bool ?? true
        self.wordReplacements = defaults.data(forKey: Keys.wordReplacements)
            .flatMap { try? JSONDecoder().decode([WordReplacement].self, from: $0) } ?? []
    }
}
