import Foundation
import Testing
@testable import Dict_app

struct MenuBarIconTests {
    @Test func foldsBandsToColumnsByPeak() {
        var spectrum = [Float](repeating: 0.1, count: 20)
        spectrum[17] = 0.9   // last group
        spectrum[2] = 0.6    // first group
        let levels = MenuBarIcon.levels(from: spectrum)
        #expect(levels.count == MenuBarIcon.columns)
        #expect(levels[0] == 0.6)
        #expect(levels[MenuBarIcon.columns - 1] == 0.9)
        #expect(levels[2] == 0.1)
    }

    @Test func emptySpectrumGivesNoLevels() {
        #expect(MenuBarIcon.levels(from: []).isEmpty)
    }

    @MainActor
    @Test func imageIsATemplateOfTheRightSize() {
        let image = MenuBarIcon.image(levels: MenuBarIcon.idleLevels)
        #expect(image.isTemplate)
        #expect(image.size.width == CGFloat(MenuBarIcon.columns) * MenuBarIcon.pitch)
        #expect(image.size.height == CGFloat(MenuBarIcon.rows) * MenuBarIcon.pitch)
    }

    /// The loading peak sweeps right, bounces off the last column, and
    /// comes back, with every frame drawing all columns.
    @Test func loadingPeakSweepsBackAndForth() {
        let peaks = (0..<10).map { frame -> Int in
            let levels = MenuBarIcon.loadingLevels(frame: frame)
            #expect(levels.count == MenuBarIcon.columns)
            return levels.indices.max { levels[$0] < levels[$1] }!
        }
        #expect(peaks == [0, 1, 2, 3, 4, 3, 2, 1, 0, 1])
    }
}
