import Foundation

/// Which Time Sheets deployment the app talks to.
///
/// The app develops against `dev` by default (as instructed by the server team).
/// The user can flip to `prod` from the menu once they're ready.
enum ServerEnvironment: String, CaseIterable, Identifiable {
    case dev
    case prod

    var id: String { rawValue }

    var baseURL: URL {
        switch self {
        case .dev:
            return URL(string: "https://timesheets-dev.lkgeorge.org/api/v1")!
        case .prod:
            return URL(string: "https://timesheets.lkgeorge.org/api/v1")!
        }
    }

    var label: String {
        switch self {
        case .dev:  return "Development"
        case .prod: return "Production"
        }
    }

    var shortLabel: String {
        switch self {
        case .dev:  return "DEV"
        case .prod: return "PROD"
        }
    }
}

/// App-wide constants.
enum AppConfig {
    /// Keychain service identifier. Tokens are stored per-environment so a dev
    /// token and a prod token can coexist without clobbering each other.
    static let keychainService = "org.lkgeorge.timesheets.menubar"

    /// UserDefaults key holding the currently selected `ServerEnvironment`.
    static let environmentDefaultsKey = "selectedEnvironment"

    /// All personal access tokens are expected to start with this prefix.
    static let tokenPrefix = "tsk_"
}
