import Foundation
import Testing
@testable import Dict_app

struct AnalyticsTests {
    /// Dashboards query these names. Renaming one silently breaks them.
    @Test func eventNamesArePinned() {
        #expect(Analytics.Event.allCases.map(\.rawValue) == [
            "app_launched",
            "dictation_completed",
            "dictation_failed",
            "onboarding_step_viewed",
            "onboarding_completed",
            "parakeet_model_downloaded",
            "license_activated",
            "trial_expired",
            "buy_clicked",
        ])
    }

    @Test func superPropertiesNameTheAppAndDropTheIP() {
        let props = Analytics.privacySuperProperties
        #expect(props["app"] as? String == "Dict")
        #expect(props["$geoip_disable"] as? Bool == true)
        #expect(props["$ip"] is NSNull)
    }

    @Test func configTurnsOffAutocaptureAndProfiles() {
        let config = Analytics.makeConfig()
        #expect(!config.captureApplicationLifecycleEvents)
        #expect(!config.captureScreenViews)
        #expect(config.personProfiles == .never)
    }

    @Test func dictationPropertiesCarryCountsNotText() {
        let props = Analytics.dictationProperties(
            text: "secret words go here", seconds: 3.14159, engine: .parakeet, style: .clean)
        #expect(props["words"] as? Int == 4)
        #expect(props["seconds"] as? Double == 3.1)
        #expect(props["engine"] as? String == "parakeet")
        #expect(props["style"] as? String == "clean")
        #expect(Set(props.keys) == ["words", "seconds", "engine", "style"])
    }

    @Test func licenseStatusNames() {
        #expect(Analytics.licenseStatusName(.trial(daysLeft: 3)) == "trial")
        #expect(Analytics.licenseStatusName(.expired) == "expired")
    }

    @Test func usageDataDefaultsOnAndRoundTrips() {
        let defaults = UserDefaults(suiteName: "AnalyticsTests-\(UUID().uuidString)")!
        let store = SettingsStore(defaults: defaults)
        #expect(store.sharesUsageData)
        var changes: [SettingsStore.Change] = []
        store.onChange = { changes.append($0) }
        store.sharesUsageData = false
        #expect(changes == [.usageData])
        #expect(!SettingsStore(defaults: defaults).sharesUsageData)
    }
}
