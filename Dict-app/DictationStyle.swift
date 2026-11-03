import Foundation

/// How much the formatter is allowed to change what was said.
enum DictationStyle: String, CaseIterable, Identifiable {
    /// Punctuation and capitalization only; every word survives.
    case verbatim
    /// Fillers out and the speaker's own corrections applied; no rewording.
    case clean
    /// Clean, plus light grammar fixes so it reads as written text.
    case polished

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .verbatim: "Verbatim"
        case .clean: "Clean"
        case .polished: "Polished"
        }
    }

    var blurb: String {
        switch self {
        case .verbatim: "Every word as spoken, with punctuation added. Ums and all."
        case .clean: "Drops ums, uhs and repeated words, and keeps only your corrected version when you change your mind mid-sentence. Never rewords."
        case .polished: "Clean, plus small grammar fixes so it reads like you typed it. Your words and meaning stay."
        }
    }
}

/// Rule-based cleanup used when the on-device model can't run (or as a
/// safety net after it does): drops filler sounds and immediate repeats.
/// Deliberately narrow so it can never change meaning.
enum FillerRemover {
    static let fillers: Set<String> = [
        "um", "umm", "ummm", "uh", "uhh", "uhm", "er", "erm", "ah", "ahh", "hmm", "hm", "mm", "mhm", "mmm",
    ]

    static func clean(_ text: String) -> String {
        var out: [Substring] = []
        var previousWord = ""
        for token in text.split(separator: " ", omittingEmptySubsequences: true) {
            let bare = token.trimmingCharacters(in: .punctuationCharacters).lowercased()
            if fillers.contains(bare) { continue }
            // "the the", "I I": a stutter, not emphasis.
            if !bare.isEmpty, bare == previousWord, token.last.map({ $0.isLetter }) ?? false, out.last?.last.map({ $0.isLetter }) ?? false {
                continue
            }
            out.append(token)
            previousWord = bare
        }
        let joined = out.joined(separator: " ")
        return joined.isEmpty ? text : joined
    }
}
