import Foundation

/// Which correction behavior the formatter should apply, derived from the app
/// being dictated into. Keeps `TranscriptFormatter` free of any AppKit or
/// bundle-ID knowledge.
enum FormattingContext {
    /// Verbatim: add punctuation and capitalization only, never change a word.
    case general
    /// Verbatim behavior plus correction of coding/terminal homophones and
    /// jargon ("Maine" → "main", "get commit" → "git commit").
    case coding
}

/// Curated allowlist of coding and terminal app bundle IDs. When the frontmost
/// app is one of these, Dict corrects domain-specific homophones and jargon
/// instead of transcribing them literally. Grown over time — add bundle IDs as
/// new tools show up.
enum CodingAppCatalog {
    static let bundleIDs: Set<String> = [
        // Terminals
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable",
        "org.alacritty",
        "io.alacritty",
        "net.kovidgoyal.kitty",
        "com.github.wez.wezterm",
        "com.raphaelamorim.rio",

        // Editors / IDEs
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.vscodium",
        "com.todesktop.230313mzl4w4u92", // Cursor
        "dev.zed.Zed",
        "com.apple.dt.Xcode",
        "com.sublimetext.4",
        "com.panic.Nova",
        "com.jetbrains.intellij",
        "com.jetbrains.intellij.ce",
        "com.jetbrains.pycharm",
        "com.jetbrains.pycharm.ce",
        "com.jetbrains.WebStorm",
        "com.jetbrains.goland",
        "com.jetbrains.CLion",
        "com.jetbrains.rubymine",
        "com.jetbrains.PhpStorm",
        "com.jetbrains.datagrip",
        "com.jetbrains.rider",
        "com.jetbrains.AppCode",
    ]

    /// True when the given bundle ID belongs to a known coding/terminal app.
    /// A nil or unknown ID is never treated as coding.
    static func isCodingApp(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return bundleIDs.contains(bundleID)
    }
}
