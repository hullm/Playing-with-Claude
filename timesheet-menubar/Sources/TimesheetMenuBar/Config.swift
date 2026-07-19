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

/// App-wide constants.
enum AppConfig {
    /// Keychain service identifier. Tokens are keyed by (service, host).
    static let keychainService = "org.lkgeorge.timesheets.menubar"

    /// UserDefaults key holding the current server hostname.
    static let serverHostDefaultsKey = "serverHost"

    /// The server used until the user changes it.
    static let defaultServerHost = "timesheets.lkgeorge.org"

    /// UserDefaults key for the "show weekends" preference (default off).
    static let showWeekendsDefaultsKey = "showWeekends"

    /// All personal access tokens are expected to start with this prefix.
    static let tokenPrefix = "tsk_"
}
