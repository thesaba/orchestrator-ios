import Observation
import ServiceManagement

/// Open at login, through `SMAppService` (works inside the sandbox, no helper app).
@MainActor
@Observable
final class LaunchAtLogin {
    private(set) var isEnabled = SMAppService.mainApp.status == .enabled
    /// The system wants the user to approve the login item in System Settings.
    private(set) var needsApproval = SMAppService.mainApp.status == .requiresApproval
    private(set) var errorMessage: String?

    func set(_ enabled: Bool) {
        errorMessage = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }

    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        needsApproval = status == .requiresApproval
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
