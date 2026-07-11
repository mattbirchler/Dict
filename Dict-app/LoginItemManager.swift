import Foundation
import ServiceManagement

/// Bridges SMAppService.mainApp into an observable toggle. The service is
/// the source of truth — nothing is stored in UserDefaults.
@MainActor
@Observable
final class LoginItemManager {
    var isEnabled: Bool {
        didSet {
            guard !isRefreshing, oldValue != isEnabled else { return }
            apply(isEnabled)
        }
    }
    private(set) var requiresApproval: Bool
    private(set) var lastError: String?
    @ObservationIgnored private var isRefreshing = false

    init() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        requiresApproval = status == .requiresApproval
    }

    func refresh() {
        isRefreshing = true
        defer { isRefreshing = false }
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        requiresApproval = status == .requiresApproval
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func apply(_ enabled: Bool) {
        lastError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            lastError = "Couldn't update login item: \(error.localizedDescription)"
        }
        refresh()
    }
}
