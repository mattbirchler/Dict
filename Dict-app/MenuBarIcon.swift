import AppKit

/// The status item's icon: a small LED grid, the HUD's dot matrix in
/// miniature. Drawn as a template image so it follows the menu bar's
/// light or dark tint; lit dots are opaque, unlit ones faint.
enum MenuBarIcon {
    static let columns = 5
    static let rows = 4
    static let pitch: CGFloat = 3.6
    static let dot: CGFloat = 2.4

    /// The resting grid: a calm little spectrum shape.
    static let idleLevels: [Float] = [0.25, 0.75, 0.5, 1.0, 0.5]

    /// A grid lit to `levels` (0...1 per column, low to high frequency).
    /// With fewer than `columns` values the rest are unlit.
    static func image(levels: [Float]) -> NSImage {
        let size = NSSize(width: CGFloat(columns) * pitch, height: CGFloat(rows) * pitch)
        let image = NSImage(size: size, flipped: false) { _ in
            for column in 0..<columns {
                let level = column < levels.count ? levels[column] : 0
                let lit = Int((Double(level) * Double(rows)).rounded())
                for row in 0..<rows {
                    let isLit = row < lit
                    let x = CGFloat(column) * pitch + (pitch - dot) / 2
                    let y = CGFloat(row) * pitch + (pitch - dot) / 2
                    NSColor.black.withAlphaComponent(isLit ? 1 : 0.22).setFill()
                    NSBezierPath(ovalIn: NSRect(x: x, y: y, width: dot, height: dot)).fill()
                }
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Dict"
        return image
    }

    /// Folds the HUD's bands down to the icon's few columns by taking the
    /// loudest band in each group, so a lit grid tracks speech visibly.
    static func levels(from spectrum: [Float]) -> [Float] {
        guard !spectrum.isEmpty else { return [] }
        let groupSize = max(1, spectrum.count / columns)
        return (0..<columns).map { column in
            let start = column * groupSize
            guard start < spectrum.count else { return 0 }
            let end = column == columns - 1 ? spectrum.count : min(spectrum.count, start + groupSize)
            return spectrum[start..<end].max() ?? 0
        }
    }
}
