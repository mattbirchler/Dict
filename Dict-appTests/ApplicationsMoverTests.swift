import Testing
@testable import Dict_app

struct ApplicationsMoverTests {
    let home = "/Users/m"

    @Test func offersWhenRunningFromDownloads() {
        #expect(ApplicationsMover.shouldOffer(bundlePath: "/Users/m/Downloads/Dict.app", isDebugBuild: false, homeDirectory: home))
    }

    @Test func offersWhenRunningFromDiskImage() {
        #expect(ApplicationsMover.shouldOffer(bundlePath: "/Volumes/Dict/Dict.app", isDebugBuild: false, homeDirectory: home))
    }

    @Test func neverOffersForDebugBuilds() {
        #expect(!ApplicationsMover.shouldOffer(bundlePath: "/Users/m/Downloads/Dict.app", isDebugBuild: true, homeDirectory: home))
    }

    @Test func neverOffersWhenAlreadyInstalled() {
        #expect(!ApplicationsMover.shouldOffer(bundlePath: "/Applications/Dict.app", isDebugBuild: false, homeDirectory: home))
        #expect(!ApplicationsMover.shouldOffer(bundlePath: "/Users/m/Applications/Dict.app", isDebugBuild: false, homeDirectory: home))
    }

    @Test func neverOffersFromDerivedData() {
        let path = "/Users/m/Library/Developer/Xcode/DerivedData/x/Build/Products/Release/Dict.app"
        #expect(!ApplicationsMover.shouldOffer(bundlePath: path, isDebugBuild: false, homeDirectory: home))
    }
}
