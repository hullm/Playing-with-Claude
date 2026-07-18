import Foundation
import ServiceManagement

/// Wrapper around `SMAppService` for the "launch at login" toggle.
///
/// This only takes effect when the app runs from a real, signed `.app` bundle
/// (i.e. built via `build_app.sh` and moved to /Applications). When run through
/// `swift run` during development there's no bundle to register, so the toggle
/// simply reports `false` and does nothing — that's expected.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns the resulting state (which may differ from `enabled` if the
    /// system refused, e.g. running unbundled).
    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        do {
            switch (enabled, SMAppService.mainApp.status) {
            case (true, let s) where s != .enabled:
                try SMAppService.mainApp.register()
            case (false, .enabled):
                try SMAppService.mainApp.unregister()
            default:
                break
            }
        } catch {
            NSLog("LaunchAtLogin: \(enabled ? "register" : "unregister") failed — \(error.localizedDescription)")
        }
        return isEnabled
    }
}
