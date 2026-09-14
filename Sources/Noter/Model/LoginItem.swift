// ABOUTME: Starts Noter at login through SMAppService, which registers the app bundle with launchd.
// ABOUTME: The user can also change this under System Settings > General > Login Items.

import Foundation
import Observation
import ServiceManagement

@Observable
final class LoginItem {
    init() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            do {
                if isEnabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                isEnabled = oldValue
            }
        }
    }
}
