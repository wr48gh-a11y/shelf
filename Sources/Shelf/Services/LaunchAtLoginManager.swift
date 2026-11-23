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
            statusNote = "Move Shelf.app to Applications to enable"
            refresh()
        }
    }
}
