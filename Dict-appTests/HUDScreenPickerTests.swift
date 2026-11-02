import CoreGraphics
import Testing
@testable import Dict_app

struct HUDScreenPickerTests {
    let left = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let right = CGRect(x: 1000, y: 0, width: 1000, height: 800)

    @Test func prefersFocusedWindowScreen() {
        let window = CGRect(x: 1200, y: 100, width: 400, height: 300)
        #expect(HUDScreenPicker.pick(screens: [left, right], focusedWindow: window, mouse: CGPoint(x: 10, y: 10)) == 1)
    }

    @Test func fallsBackToMouse() {
        #expect(HUDScreenPicker.pick(screens: [left, right], focusedWindow: nil, mouse: CGPoint(x: 1500, y: 10)) == 1)
    }

    @Test func fallsBackToFirstScreen() {
        #expect(HUDScreenPicker.pick(screens: [left, right], focusedWindow: nil, mouse: CGPoint(x: -50, y: -50)) == 0)
        #expect(HUDScreenPicker.pick(screens: [], focusedWindow: nil, mouse: .zero) == nil)
    }
}
