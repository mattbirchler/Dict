import Testing
@testable import Dict_app

struct CodingAppCatalogTests {
    @Test func recognizesKnownCodingApps() {
        #expect(CodingAppCatalog.isCodingApp("com.apple.Terminal"))
        #expect(CodingAppCatalog.isCodingApp("com.googlecode.iterm2"))
        #expect(CodingAppCatalog.isCodingApp("com.microsoft.VSCode"))
        #expect(CodingAppCatalog.isCodingApp("dev.zed.Zed"))
        #expect(CodingAppCatalog.isCodingApp("com.apple.dt.Xcode"))
    }

    @Test func rejectsNonCodingApps() {
        #expect(!CodingAppCatalog.isCodingApp("com.apple.Safari"))
        #expect(!CodingAppCatalog.isCodingApp("com.apple.mail"))
        #expect(!CodingAppCatalog.isCodingApp("com.apple.Notes"))
    }

    @Test func rejectsUnknownAndNil() {
        #expect(!CodingAppCatalog.isCodingApp("com.example.definitely-not-real"))
        #expect(!CodingAppCatalog.isCodingApp(nil))
    }
}
