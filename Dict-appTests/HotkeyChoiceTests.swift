import CoreGraphics
import Foundation
import Testing
@testable import Dict_app

struct HotkeyChoiceTests {
    @Test func presetsKeepTheirOldStorageNames() {
        #expect(HotkeyChoice.rightCommand.storageKey == "rightCommand")
        #expect(HotkeyChoice(storageKey: "fn") == .fn)
        #expect(HotkeyChoice(storageKey: "nope") == nil)
    }

    @Test func customComboRoundTripsThroughStorage() {
        let combo = HotkeyChoice.custom(keycode: 49, modifiers: 1 << 19, label: "Space")
        let key = combo.storageKey
        #expect(HotkeyChoice(storageKey: key) == combo)
        #expect(combo.glyph == "⌥Space")
        #expect(combo.displayName == "⌥Space")
        #expect(HotkeyChoice(storageKey: "custom:49:x:Space") == nil)
        #expect(HotkeyChoice(storageKey: "custom:49:0:") == nil)
    }

    @Test func labelsWithColonsSurvive() {
        let combo = HotkeyChoice.custom(keycode: 41, modifiers: 0, label: ":")
        #expect(HotkeyChoice(storageKey: combo.storageKey) == combo)
    }

    @Test func modifierGlyphsFollowMacOSOrder() {
        let all: UInt64 = (1 << 20) | (1 << 19) | (1 << 18) | (1 << 17)
        #expect(HotkeyChoice.modifierGlyphs(all) == "⌃⌥⇧⌘")
        #expect(HotkeyChoice.modifierGlyphs(0) == "")
    }

    @Test func customMatchesOnlyItsExactModifiers() {
        let combo = HotkeyChoice.custom(keycode: 49, modifiers: 1 << 19, label: "Space")
        #expect(combo.matchesKeyDown(keycode: 49, flags: .maskAlternate))
        // Caps Lock or the fn bit riding along must not break the match.
        #expect(combo.matchesKeyDown(keycode: 49, flags: [.maskAlternate, .maskAlphaShift, .maskSecondaryFn]))
        #expect(!combo.matchesKeyDown(keycode: 49, flags: [.maskAlternate, .maskCommand]))
        #expect(!combo.matchesKeyDown(keycode: 49, flags: []))
        #expect(!combo.matchesKeyDown(keycode: 50, flags: .maskAlternate))
        #expect(!HotkeyChoice.rightCommand.matchesKeyDown(keycode: 54, flags: .maskCommand), "presets use flagsChanged")
    }

    @MainActor
    @Test func customHotkeyPersistsInSettings() {
        let name = "HotkeyChoiceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        store.hotkey = .custom(keycode: 79, modifiers: 0, label: "F18")
        #expect(SettingsStore(defaults: defaults).hotkey == .custom(keycode: 79, modifiers: 0, label: "F18"))
    }
}
