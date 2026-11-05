import Foundation
import PostHog

/// Anonymous usage counts sent to PostHog. `import PostHog` stays in this
/// file so the rest of the app only sees `Analytics.shared.log(...)`.
///
/// What is never sent: audio, transcript text, replacements, the license key
/// or its email, and the IP address (see `privacySuperProperties`). People
/// can turn all of it off in Settings.
final class Analytics {
    static let shared = Analytics()

    /// The "Birchtree Apps" project, shared with Bench, Quick Subtitles and
    /// other small apps. The `app` property tells them apart.
    private static let projectToken = "phc_rBkGD8e38uUJjekGXqxFiBGNaJnDQf8A5TADoNRehTAc"
    private static let host = "https://us.i.posthog.com"
    static let appName = "Dict"

    private init() {}

    /// Event names. Raw values are pinned by AnalyticsTests: renaming one
    /// breaks existing dashboards.
    enum Event: String, CaseIterable {
        case appLaunched = "app_launched"
        case dictationCompleted = "dictation_completed"
        case dictationFailed = "dictation_failed"
        case onboardingStepViewed = "onboarding_step_viewed"
        case onboardingCompleted = "onboarding_completed"
        case parakeetModelDownloaded = "parakeet_model_downloaded"
        case licenseActivated = "license_activated"
        case trialExpired = "trial_expired"
        case buyClicked = "buy_clicked"
    }

    /// True under XCTest. Tests run inside the real app, so without this
    /// every test run would send production events.
    static var isRunningInTests: Bool {
        NSClassFromString("XCTestCase") != nil
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Merged into every event. `$geoip_disable` stops PostHog looking up a
    /// location, and a null `$ip` keeps the address from being stored at
    /// all. Both are needed: the first alone still lets the IP through.
    static var privacySuperProperties: [String: Any] {
        ["app": appName, "$geoip_disable": true, "$ip": NSNull()]
    }

    /// Split out from `setup` so the privacy settings are testable, since
    /// `setup` does nothing under XCTest.
    static func makeConfig() -> PostHogConfig {
        let config = PostHogConfig(projectToken: projectToken, host: host)
        // Off: on macOS this fires on every reactivation, and Dict is a menu
        // bar app that's activated constantly. app_launched replaces it.
        config.captureApplicationLifecycleEvents = false
        config.captureScreenViews = false
        // Never create person profiles. Events stay anonymous counts.
        config.personProfiles = .never
        #if DEBUG
        config.debug = true
        #endif
        return config
    }

    private var hasSetUp = false

    /// Starts PostHog and sends `app_launched`. When `enabled` is false the
    /// SDK is opted out before anything is sent.
    func setup(enabled: Bool, launchProperties: [String: Any]) {
        guard !Self.isRunningInTests, !hasSetUp else { return }
        hasSetUp = true
        PostHogSDK.shared.setup(Self.makeConfig())
        setEnabled(enabled)
        PostHogSDK.shared.register(Self.privacySuperProperties)
        log(.appLaunched, properties: launchProperties)
    }

    /// Follows the Settings toggle. While opted out, PostHog drops every
    /// capture instead of queueing it.
    func setEnabled(_ enabled: Bool) {
        guard !Self.isRunningInTests, hasSetUp else { return }
        if enabled {
            PostHogSDK.shared.optIn()
        } else {
            PostHogSDK.shared.optOut()
        }
    }

    func log(_ event: Event, properties: [String: Any] = [:]) {
        guard !Self.isRunningInTests, hasSetUp else { return }
        PostHogSDK.shared.capture(event.rawValue, properties: properties.isEmpty ? nil : properties)
    }
}

// MARK: - Event properties

extension Analytics {
    /// Seconds are rounded to one decimal and words counted, so nothing about
    /// what was said can be recovered.
    static func dictationProperties(text: String, seconds: Double,
                                    engine: TranscriptionEngineChoice,
                                    style: DictationStyle) -> [String: Any] {
        [
            "words": DictationStats.wordCount(text),
            "seconds": (seconds * 10).rounded() / 10,
            "engine": engine.rawValue,
            "style": style.rawValue,
        ]
    }

    /// "trial", "licensed" or "expired", without anything from the key.
    static func licenseStatusName(_ status: LicenseStore.Status) -> String {
        switch status {
        case .licensed: "licensed"
        case .trial: "trial"
        case .expired: "expired"
        }
    }
}
