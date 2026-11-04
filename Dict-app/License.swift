import Foundation
import CryptoKit

/// A purchased copy of Dict, read from a license key.
///
/// Keys are checked on this Mac with Dict's public key; nothing is sent
/// anywhere. The format is made by server/lib/license.mjs:
///
///     DICT1-<payload>.<signature>
///
/// payload is base64url JSON, signature is the base64url Ed25519 signature
/// of the payload's bytes.
struct License: Equatable {
    let email: String
    let purchase: String
    /// The purchase date as YYYY-MM-DD.
    let issued: String
    /// The key exactly as it was verified, for saving.
    let key: String

    /// The public half of the key in scripts/license-keygen.sh.
    static let publicKey = "5kDspUaV8t1jM5hneegcW3qfqY0zNLUeB6x/eLy96NY="

    enum Problem: Error, Equatable {
        /// Nothing that looks like a Dict key was found in the text.
        case notAKey
        /// It looks like a key, but this public key didn't sign it.
        case invalid

        var message: String {
            switch self {
            case .notAKey: "That doesn't look like a Dict license key. It starts with DICT1-."
            case .invalid: "That license key isn't valid. Check that it was copied in full."
            }
        }
    }

    private struct Payload: Decodable {
        let v: Int
        let product: String
        let email: String
        let purchase: String
        let issued: String
    }

    /// Finds a key in pasted text (a bare key, a sentence from the email,
    /// or the activation link) and checks its signature.
    static func verify(_ text: String, publicKey: String = publicKey) throws(Problem) -> License {
        guard let key = extractKey(from: text) else {
            throw text.contains("DICT1-") ? .invalid : .notAKey
        }
        let parts = key.dropFirst("DICT1-".count).split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let payloadData = Data(base64URL: String(parts[0])),
              let signature = Data(base64URL: String(parts[1])),
              let keyData = Data(base64Encoded: publicKey),
              let signer = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
              signer.isValidSignature(signature, for: payloadData),
              let payload = try? JSONDecoder().decode(Payload.self, from: payloadData),
              payload.v == 1, payload.product == "dict"
        else { throw .invalid }
        return License(email: payload.email, purchase: payload.purchase, issued: payload.issued, key: key)
    }

    /// Email clients wrap long lines and links percent-encode, so spaces
    /// and line breaks are dropped and the link form is decoded first. An
    /// Ed25519 signature is always 86 base64url characters, which keeps
    /// text that follows the key from running into it.
    static func extractKey(from text: String) -> String? {
        let decoded = text.removingPercentEncoding ?? text
        let joined = decoded.filter { !$0.isWhitespace }
        guard let match = joined.firstMatch(of: #/DICT1-[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]{86}/#) else { return nil }
        return String(match.output)
    }
}

extension Data {
    /// Base64url without padding, as the key format uses.
    init?(base64URL: String) {
        var base64 = base64URL.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }
}

/// When the free trial started. It's written in two places (preferences and
/// a file next to the history) and the earlier one wins, so clearing one of
/// them doesn't restart the trial. This is a nudge, not DRM.
struct TrialClock {
    static let length: TimeInterval = 14 * 24 * 60 * 60

    let defaults: UserDefaults
    let markerURL: URL

    static let defaultsKey = "trialStartedAt"

    static var standardMarkerURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Dict/Trial", directoryHint: .notDirectory)
    }

    /// The trial's start, recorded as `now` the first time it's asked.
    func startDate(now: Date) -> Date {
        let stored = [defaults.object(forKey: Self.defaultsKey) as? Date, readMarker()].compactMap { $0 }
        let start = stored.min() ?? now
        if defaults.object(forKey: Self.defaultsKey) as? Date != start {
            defaults.set(start, forKey: Self.defaultsKey)
        }
        if readMarker() != start { writeMarker(start) }
        return start
    }

    private func readMarker() -> Date? {
        guard let text = try? String(contentsOf: markerURL, encoding: .utf8),
              let seconds = TimeInterval(text.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    private func writeMarker(_ date: Date) {
        try? FileManager.default.createDirectory(at: markerURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? String(date.timeIntervalSince1970).write(to: markerURL, atomically: true, encoding: .utf8)
    }
}

/// Whether this copy of Dict is paid for, in trial, or past its trial.
@MainActor
@Observable
final class LicenseStore {
    enum Status: Equatable {
        case licensed(License)
        case trial(daysLeft: Int)
        case expired

        var allowsDictation: Bool {
            if case .expired = self { return false }
            return true
        }
    }

    /// Where people buy Dict. The checkout sends them back with a key.
    static let purchaseURL = URL(string: "https://dictapp.app/buy")!

    private(set) var license: License?
    /// Why the last activation link didn't work, for the License screen.
    var linkProblem: String?
    private let defaults: UserDefaults
    private let publicKey: String
    private let trialStart: Date
    private let now: () -> Date

    static let keyDefaultsKey = "licenseKey"

    init(defaults: UserDefaults = .standard,
         trial: TrialClock? = nil,
         publicKey: String = License.publicKey,
         now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        self.publicKey = publicKey
        let clock = trial ?? TrialClock(defaults: defaults, markerURL: TrialClock.standardMarkerURL)
        trialStart = clock.startDate(now: now())
        if let saved = defaults.string(forKey: Self.keyDefaultsKey) {
            license = try? License.verify(saved, publicKey: publicKey)
        }
    }

    var status: Status {
        if let license { return .licensed(license) }
        let remaining = trialStart.addingTimeInterval(TrialClock.length).timeIntervalSince(now())
        guard remaining > 0 else { return .expired }
        return .trial(daysLeft: Int((remaining / 86_400).rounded(.up)))
    }

    /// Checks and saves a key. Throws with a message to show if it's bad.
    @discardableResult
    func activate(_ text: String) throws(License.Problem) -> License {
        let verified = try License.verify(text, publicKey: publicKey)
        defaults.set(verified.key, forKey: Self.keyDefaultsKey)
        license = verified
        linkProblem = nil
        return verified
    }

    /// Forgets the key on this Mac, for moving it to another one.
    func deactivate() {
        defaults.removeObject(forKey: Self.keyDefaultsKey)
        license = nil
    }
}
