import ServiceManagement
import os.log

enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func toggle() {
        do {
            if isEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            os_log("LaunchAtLogin toggle failed: %{public}@", String(describing: error))
        }
    }
}
