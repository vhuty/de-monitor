import ServiceManagement
import Foundation

/// Autostart via SMAppService (macOS 13+). Requires the app to be a bundled
/// .app for `mainAppService` to work; falls back gracefully in dev builds
/// run from `swift run` (toggle will report the error in Console).
public enum Autostart {
    public static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
