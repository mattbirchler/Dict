import Foundation
import Testing
@testable import Dict_app

/// The key below was signed by server/lib/license.mjs with a test seed
/// (bytes 1 through 32), so these tests also check that the server and the
/// app agree on the format.
struct LicenseTests {
    static let testPublicKey = "ebVWLo/mVPlAeLES6KmLp5AfhTrmlb7X4OORC60ElmQ="
    static let key = "DICT1-eyJ2IjoxLCJwcm9kdWN0IjoiZGljdCIsImVtYWlsIjoiYnV5ZXJAZXhhbXBsZS5jb20iLCJwdXJjaGFzZSI6ImNzX3Rlc3RfMTIzIiwiaXNzdWVkIjoiMjAyNi0xMS0wNCJ9.6-tumXTcaevaLpsXrXm7ulAM8H5E7kVf0CM91P870_bI16cGUKn3o7XZO953dpmJ-RLqxg2lW4YXwHqHfGH1CA"
    /// The same payload signed with a different private key.
    static let forged = "DICT1-eyJ2IjoxLCJwcm9kdWN0IjoiZGljdCIsImVtYWlsIjoiYnV5ZXJAZXhhbXBsZS5jb20iLCJwdXJjaGFzZSI6ImNzX3Rlc3RfMTIzIiwiaXNzdWVkIjoiMjAyNi0xMS0wNCJ9.fDhiGxUvJkX7wThrHDMkZZkOhxp_7tfhWhs6KLgZnaTyVjh9mRHWmLTdhT9FlU4RwozCGhju_lmv7aq4WbGCAw"

    @Test func validKeyReadsBack() throws {
        let license = try License.verify(Self.key, publicKey: Self.testPublicKey)
        #expect(license.email == "buyer@example.com")
        #expect(license.purchase == "cs_test_123")
        #expect(license.issued == "2026-11-04")
        #expect(license.key == Self.key)
    }

    @Test func keySignedByAnotherKeyIsRejected() {
        #expect(throws: License.Problem.invalid) {
            try License.verify(Self.forged, publicKey: Self.testPublicKey)
        }
    }

    @Test func testKeyIsNotValidForTheRealApp() {
        #expect(throws: License.Problem.invalid) { try License.verify(Self.key) }
    }

    @Test func editedPayloadIsRejected() {
        // Swap one payload character: the signature no longer matches.
        var chars = Array(Self.key)
        chars[10] = chars[10] == "A" ? "B" : "A"
        #expect(throws: License.Problem.invalid) {
            try License.verify(String(chars), publicKey: Self.testPublicKey)
        }
    }

    @Test func truncatedKeyIsRejected() {
        #expect(throws: License.Problem.invalid) {
            try License.verify(String(Self.key.dropLast(20)), publicKey: Self.testPublicKey)
        }
    }

    @Test func textWithoutAKeyIsNotAKey() {
        #expect(throws: License.Problem.notAKey) { try License.verify("hello", publicKey: Self.testPublicKey) }
        #expect(throws: License.Problem.notAKey) { try License.verify("", publicKey: Self.testPublicKey) }
    }

    @Test func keyIsFoundInSurroundingTextAndWrappedLines() throws {
        let middle = Self.key.index(Self.key.startIndex, offsetBy: 80)
        let wrapped = "Your Dict license key:\n  " + Self.key[..<middle] + "\n  " + Self.key[middle...] + "\nThanks!"
        #expect(try License.verify(wrapped, publicKey: Self.testPublicKey).key == Self.key)
    }

    @Test func keyIsFoundInTheActivationLink() throws {
        let link = "dictapp://activate?key=" + Self.key.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        #expect(try License.verify(link, publicKey: Self.testPublicKey).key == Self.key)
    }
}

@MainActor
struct LicenseStoreTests {
    private func makeDefaults() -> UserDefaults {
        let name = "LicenseStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func markerURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "dict-trial-\(UUID().uuidString)/Trial")
    }

    private let day: TimeInterval = 86_400
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeStore(defaults: UserDefaults, marker: URL, at date: Date) -> LicenseStore {
        LicenseStore(
            defaults: defaults,
            trial: TrialClock(defaults: defaults, markerURL: marker),
            publicKey: LicenseTests.testPublicKey,
            now: { date }
        )
    }

    @Test func trialCountsDownFromFirstLaunch() {
        let defaults = makeDefaults(), marker = markerURL()
        #expect(makeStore(defaults: defaults, marker: marker, at: start).status == .trial(daysLeft: 14))
        #expect(makeStore(defaults: defaults, marker: marker, at: start + 0.5 * day).status == .trial(daysLeft: 14))
        #expect(makeStore(defaults: defaults, marker: marker, at: start + 13.5 * day).status == .trial(daysLeft: 1))
        #expect(makeStore(defaults: defaults, marker: marker, at: start + 14 * day).status == .expired)
    }

    @Test func expiredTrialBlocksDictation() {
        let defaults = makeDefaults(), marker = markerURL()
        _ = makeStore(defaults: defaults, marker: marker, at: start)
        let later = makeStore(defaults: defaults, marker: marker, at: start + 30 * day)
        #expect(later.status.allowsDictation == false)
    }

    @Test func clearingPreferencesDoesNotRestartTheTrial() {
        let marker = markerURL()
        _ = makeStore(defaults: makeDefaults(), marker: marker, at: start)
        let fresh = makeStore(defaults: makeDefaults(), marker: marker, at: start + 20 * day)
        #expect(fresh.status == .expired)
    }

    @Test func deletingTheMarkerDoesNotRestartTheTrial() throws {
        let defaults = makeDefaults(), marker = markerURL()
        _ = makeStore(defaults: defaults, marker: marker, at: start)
        try FileManager.default.removeItem(at: marker)
        #expect(makeStore(defaults: defaults, marker: marker, at: start + 20 * day).status == .expired)
    }

    @Test func activatingUnlocksAndPersists() throws {
        let defaults = makeDefaults(), marker = markerURL()
        _ = makeStore(defaults: defaults, marker: marker, at: start)
        let store = makeStore(defaults: defaults, marker: marker, at: start + 30 * day)
        #expect(store.status == .expired)

        let license = try store.activate(LicenseTests.key)
        #expect(store.status == .licensed(license))
        #expect(store.status.allowsDictation)

        let relaunched = makeStore(defaults: defaults, marker: marker, at: start + 31 * day)
        #expect(relaunched.status == .licensed(license))
    }

    @Test func badKeyLeavesStatusAlone() {
        let defaults = makeDefaults(), marker = markerURL()
        let store = makeStore(defaults: defaults, marker: marker, at: start)
        #expect(throws: License.Problem.invalid) { try store.activate(LicenseTests.forged) }
        #expect(store.status == .trial(daysLeft: 14))
        #expect(defaults.string(forKey: LicenseStore.keyDefaultsKey) == nil)
    }

    @Test func deactivatingReturnsToTheTrialState() throws {
        let defaults = makeDefaults(), marker = markerURL()
        let store = makeStore(defaults: defaults, marker: marker, at: start + 30 * day)
        try store.activate(LicenseTests.key)
        store.deactivate()
        #expect(store.status == .trial(daysLeft: 14))  // this store's trial began at its own first launch
        #expect(makeStore(defaults: defaults, marker: marker, at: start + 31 * day).license == nil)
    }

    @Test func tamperedSavedKeyIsIgnored() {
        let defaults = makeDefaults(), marker = markerURL()
        defaults.set(LicenseTests.forged, forKey: LicenseStore.keyDefaultsKey)
        #expect(makeStore(defaults: defaults, marker: marker, at: start).license == nil)
    }
}

@MainActor
struct TrialLockTests {
    private func store(expired: Bool) -> LicenseStore {
        let name = "TrialLockTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let marker = FileManager.default.temporaryDirectory.appending(path: "dict-trial-\(UUID().uuidString)/Trial")
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let clock = TrialClock(defaults: defaults, markerURL: marker)
        _ = clock.startDate(now: start)
        return LicenseStore(defaults: defaults, trial: clock, publicKey: LicenseTests.testPublicKey,
                            now: { start + (expired ? 15 : 1) * 86_400 })
    }

    @Test func expiredTrialBlocksTheHotkeyWithAReason() {
        let name = "TrialLockTests-\(UUID().uuidString)"
        let state = AppState(settings: SettingsStore(defaults: UserDefaults(suiteName: name)!), license: store(expired: true))
        #expect(state.canStartRecording == false)
        #expect(state.startBlockedReason == "Trial over. Buy Dict to keep dictating")
    }

    @Test func trialDoesNotAddABlockReason() {
        let name = "TrialLockTests-\(UUID().uuidString)"
        let state = AppState(settings: SettingsStore(defaults: UserDefaults(suiteName: name)!), license: store(expired: false))
        #expect(state.startBlockedReason != "Trial over. Buy Dict to keep dictating")
    }

    @Test func menuShowsTrialStateUntilLicensed() throws {
        #expect(MenuBarManager.licenseStatusTitle(.trial(daysLeft: 9)) == "Free trial: 9 days left")
        #expect(MenuBarManager.licenseStatusTitle(.trial(daysLeft: 1)) == "Free trial: 1 day left")
        #expect(MenuBarManager.licenseStatusTitle(.expired) == "Free trial ended")
        let license = try License.verify(LicenseTests.key, publicKey: LicenseTests.testPublicKey)
        #expect(MenuBarManager.licenseStatusTitle(.licensed(license)) == nil)
    }

    @Test func purchaseDateReadsNaturally() {
        #expect(LicenseView.purchaseDate("2026-11-04").contains("2026"))
        #expect(LicenseView.purchaseDate("garbage") == "garbage")
    }
}
