import Foundation

/// The Time Sheets server the app talks to, identified by hostname (the user can
/// change it). Tokens are stored per-host so different servers don't collide.
enum Server {
    /// Clean up user-entered text into a bare hostname:
    /// "https://Timesheets.LKGeorge.org/api/v1/" → "timesheets.lkgeorge.org".
    static func normalizeHost(_ raw: String) -> String {
        var h = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let scheme = h.range(of: "://") { h = String(h[scheme.upperBound...]) }
        if let slash = h.firstIndex(of: "/") { h = String(h[..<slash]) }
        if let at = h.lastIndex(of: "@") { h = String(h[h.index(after: at)...]) } // strip creds
        return h.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// Whether a normalized host is plausibly a real hostname.
    static func isValidHost(_ host: String) -> Bool {
        let h = normalizeHost(host)
        return !h.isEmpty && h.contains(".") && !h.contains(" ")
    }

    /// The REST base, e.g. https://timesheets.lkgeorge.org/api/v1
    static func baseURL(host: String) -> URL? {
        URL(string: "https://\(normalizeHost(host))/api/v1")
    }

    /// The web app root, e.g. https://timesheets.lkgeorge.org
    static func webURL(host: String) -> URL? {
        URL(string: "https://\(normalizeHost(host))")
    }
}

/// A server the app can point at, identified by its normalized host. Tokens are
/// stored per host, so each server keeps its own credential.
struct ServerInfo: Codable, Equatable, Identifiable {
    var name: String
    var host: String
    var isBuiltIn: Bool
    var id: String { host }

    enum Badge { case prod, dev, custom }
    var badge: Badge {
        switch host {
        case AppConfig.productionHost: return .prod
        case AppConfig.developmentHost: return .dev
        default: return .custom
        }
    }
    var badgeLabel: String {
        switch badge {
        case .prod: return "PROD"
        case .dev: return "DEV"
        case .custom: return "CUSTOM"
        }
    }
}

/// App-wide constants.
enum AppConfig {
    /// Keychain service identifier. Tokens are keyed by (service, host).
    static let keychainService = "org.lkgeorge.timesheets.menubar"

    /// UserDefaults key holding the current server hostname.
    static let serverHostDefaultsKey = "serverHost"

    /// UserDefaults key holding the user's custom servers ([ServerInfo] as JSON).
    static let customServersDefaultsKey = "customServers"

    /// UserDefaults key holding per-host token prefixes ([host: "tsk_…12"]).
    /// The prefix is the public identifier the website shows — safe to store here.
    static let tokenPrefixesDefaultsKey = "tokenPrefixes"

    static let productionHost = "timesheets.lkgeorge.org"
    static let developmentHost = "timesheets-dev.lkgeorge.org"

    /// The server used until the user changes it (production).
    static let defaultServerHost = productionHost

    /// The always-present servers, production first.
    static let builtInServers: [ServerInfo] = [
        ServerInfo(name: "Production", host: productionHost, isBuiltIn: true),
        ServerInfo(name: "Development", host: developmentHost, isBuiltIn: true)
    ]

    /// UserDefaults key for the "show weekends" preference (default off).
    static let showWeekendsDefaultsKey = "showWeekends"

    /// UserDefaults key for showing every past timesheet vs. collapsing old
    /// completed ones (default off = collapse).
    static let showAllPeriodsDefaultsKey = "showAllPeriods"

    /// All personal access tokens are expected to start with this prefix.
    static let tokenPrefix = "tsk_"

    /// Displayed app version (keep in sync with Info.plist CFBundleShortVersionString).
    static let appVersion = "1.0.3"
}
