import Foundation
import Observation
import ServiceManagement

@MainActor
@Observable
final class LaunchAtLoginManager {
    var isEnabled: Bool = false
    var statusNote: String? = nil

    init() {
        refresh()
    }

    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = (status == .enabled)
        switch status {
        case .requiresApproval:
            statusNote = "Approve Shelf in System Settings → Login Items"
        default:
            statusNote = nil
        }
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refresh()
        } catch {
            refresh()
            // refresh() may already show a more specific note (e.g. approval pending)
            if statusNote == nil {
                statusNote = enabled
                    ? "Could not enable Launch at Login (move Shelf.app to Applications)"
                    : "Could not disable Launch at Login"
            }
        }
    }
}
