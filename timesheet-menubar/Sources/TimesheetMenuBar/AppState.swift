import Foundation
import SwiftUI
import AppKit

/// Central observable state for the menu bar UI.
///
/// Owns the server hostname + token, and drives all API traffic. Views observe
/// this and call its `async` action methods.
@MainActor
final class AppState: ObservableObject {

    // Configuration
    @Published private(set) var serverHost: String
    @Published private(set) var hasToken: Bool
    @Published var launchAtLogin: Bool
    /// When true, show the server-management screen.
    @Published var editingServers = false
    /// When true, show the default-hours editor.
    @Published var editingDefaults = false

    /// User-added custom servers (built-ins live in AppConfig).
    @Published private(set) var customServers: [ServerInfo]
    /// Hosts that currently have a stored token (kept in sync explicitly so the
    /// UI updates; each entry is a prompt-free existence check).
    @Published private(set) var serversWithToken: Set<String> = []
    /// host → first-12-char token prefix, for an identifying label. This prefix
    /// is the public identifier the website shows, so UserDefaults is fine.
    @Published private(set) var tokenPrefixes: [String: String]

    /// Show weekend rows in the day list (default off — empty weekends hide).
    @Published var showWeekends: Bool {
        didSet { UserDefaults.standard.set(showWeekends, forKey: AppConfig.showWeekendsDefaultsKey) }
    }

    /// Show every past timesheet (default off collapses old completed ones,
    /// keeping only the most recent completed period in the picker).
    @Published var showAllPeriods: Bool {
        didSet { UserDefaults.standard.set(showAllPeriods, forKey: AppConfig.showAllPeriodsDefaultsKey) }
    }

    /// In-memory copy of the token so we read the Keychain at most once per
    /// launch (each read can trigger an OS access prompt for unsigned builds).
    private var cachedToken: String?

    // Loaded data
    @Published private(set) var me: Me?
    @Published private(set) var periods: [Period] = []
    @Published private(set) var timesheet: Timesheet?

    // UI status
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    /// Set when a 401 happens so the UI can force the token-entry screen.
    @Published var needsReauth = false
    @Published var lastRefreshed: Date?

    /// Current date ("YYYY-MM-DD", US Eastern). Published so the "Today" marker
    /// stays correct in this long-running menu bar app: updating it re-renders
    /// the view even when it wouldn't otherwise refresh on open.
    @Published private(set) var today: String

    init() {
        let host = UserDefaults.standard.string(forKey: AppConfig.serverHostDefaultsKey)
            ?? AppConfig.defaultServerHost
        self.serverHost = host
        self.hasToken = Keychain.hasToken(for: host)
        self.launchAtLogin = LaunchAtLogin.isEnabled
        self.showWeekends = UserDefaults.standard.bool(forKey: AppConfig.showWeekendsDefaultsKey)
        self.showAllPeriods = UserDefaults.standard.bool(forKey: AppConfig.showAllPeriodsDefaultsKey)
        if let data = UserDefaults.standard.data(forKey: AppConfig.customServersDefaultsKey),
           let list = try? JSONDecoder().decode([ServerInfo].self, from: data) {
            self.customServers = list
        } else {
            self.customServers = []
        }
        self.tokenPrefixes = UserDefaults.standard.dictionary(forKey: AppConfig.tokenPrefixesDefaultsKey)
            as? [String: String] ?? [:]
        self.today = DateParsing.todayString()
        refreshTokenStatus()
        startClock()
    }

    /// Watch for the day rolling over — periodically, on the system day-change
    /// notification, and on wake from sleep (which can cross midnight).
    private func startClock() {
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.tick() } }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.tick() } }
    }

    /// Refresh the current date; if the day changed, reload so the sheet and the
    /// "Today" highlight are current. Also called when the menu opens.
    func tick() {
        let now = DateParsing.todayString()
        guard now != today else { return }
        today = now
        if hasToken && !needsReauth {
            Task { await loadEverything() }
        }
    }

    /// Periods to show in the picker. When `showAllPeriods` is off, keep every
    /// non-completed period plus only the most recent completed one — and always
    /// keep whatever period is currently loaded so the picker's selection stays
    /// valid. Assumes `periods` is newest-first (as the API returns them).
    var visiblePeriods: [Period] {
        guard !showAllPeriods else { return periods }
        let loadedID = timesheet?.id
        var keptCompleted = false
        return periods.filter { period in
            guard period.isCompleted else { return true }
            if keptCompleted { return period.id == loadedID }
            keptCompleted = true
            return true
        }
    }

    /// How many completed periods are hidden right now (for the menu label).
    var hiddenCompletedCount: Int {
        showAllPeriods ? 0 : periods.count - visiblePeriods.count
    }

    // MARK: - Servers

    /// Built-in servers plus the user's custom ones.
    var knownServers: [ServerInfo] { AppConfig.builtInServers + customServers }

    /// The server the app is currently pointed at.
    var selectedServer: ServerInfo {
        knownServers.first { $0.host == serverHost }
            ?? ServerInfo(name: serverHost, host: serverHost, isBuiltIn: false)
    }

    func tokenPrefix(for host: String) -> String? { tokenPrefixes[host] }

    func beginEditingServers() {
        errorMessage = nil
        editingServers = true
    }

    func cancelEditingServers() {
        errorMessage = nil
        editingServers = false
    }

    /// Point the app at a different server. Never touches any stored token — if
    /// the target already has one it's reused immediately (no re-paste); if not,
    /// the UI drops to the add-token state for that server.
    func selectServer(_ rawHost: String) {
        let host = Server.normalizeHost(rawHost)
        editingServers = false
        errorMessage = nil
        guard host != serverHost else { return }
        applyServerHost(host)          // persists, resets loaded data, re-checks token
        if hasToken {
            Task { await loadEverything() }
        }
    }

    /// Add a custom server and select it. Returns an error message, or nil.
    @discardableResult
    func addCustomServer(name rawName: String, host rawHost: String) -> String? {
        let host = Server.normalizeHost(rawHost)
        guard Server.isValidHost(host) else {
            return "Enter a valid server, like timesheets.example.org."
        }
        guard !knownServers.contains(where: { $0.host == host }) else {
            return "That server is already in the list."
        }
        let trimmed = rawName.trimmingCharacters(in: .whitespaces)
        customServers.append(ServerInfo(name: trimmed.isEmpty ? host : trimmed,
                                        host: host, isBuiltIn: false))
        persistCustomServers()
        selectServer(host)
        return nil
    }

    /// Remove a custom server (and its token). Built-ins can't be removed.
    func removeCustomServer(_ host: String) {
        guard customServers.contains(where: { $0.host == host }) else { return }
        customServers.removeAll { $0.host == host }
        persistCustomServers()
        Keychain.deleteToken(for: host)
        setTokenPrefix(nil, for: host)
        refreshTokenStatus()
        if host == serverHost { selectServer(AppConfig.defaultServerHost) }
    }

    /// Remove the token for one server only, leaving every other server intact.
    func removeToken(for host: String) {
        Keychain.deleteToken(for: host)
        setTokenPrefix(nil, for: host)
        if host == serverHost {
            cachedToken = nil
            hasToken = false
            resetLoadedState()
        }
        refreshTokenStatus()
    }

    private func persistCustomServers() {
        if let data = try? JSONEncoder().encode(customServers) {
            UserDefaults.standard.set(data, forKey: AppConfig.customServersDefaultsKey)
        }
    }

    private func refreshTokenStatus() {
        serversWithToken = Set(knownServers.filter { Keychain.hasToken(for: $0.host) }.map(\.host))
    }

    private func setTokenPrefix(_ prefix: String?, for host: String) {
        tokenPrefixes[host] = prefix
        UserDefaults.standard.set(tokenPrefixes, forKey: AppConfig.tokenPrefixesDefaultsKey)
    }

    // MARK: - Default hours

    func beginEditingDefaults() {
        errorMessage = nil
        editingDefaults = true
    }

    func cancelEditingDefaults() {
        errorMessage = nil
        editingDefaults = false
    }

    /// Fetch the user's current default workday hours.
    func loadDefaults() async -> WorkdayDefaults? {
        guard let client = makeClient() else { return nil }
        do {
            return try await client.defaults()
        } catch {
            handle(error)
            return nil
        }
    }

    /// Save new default hours (24-hour "HH:MM"). Returns nil on success, or a
    /// message to show on failure (e.g. a 422 validation error).
    func saveDefaults(regStart: String, regEnd: String) async -> String? {
        guard let client = makeClient() else { return "Not signed in." }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            _ = try await client.updateDefaults(regStart: regStart, regEnd: regEnd)
            editingDefaults = false
            // Reflect the new defaults in the loaded card's blank (pre-fill) days.
            if let ts = timesheet {
                self.timesheet = try? await client.timesheet(periodID: ts.id)
            }
            return nil
        } catch APIError.conflict(let message) {
            return message   // 422 — invalid times / end not after start
        } catch {
            handle(error)
            return (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func applyServerHost(_ rawHost: String) {
        let host = Server.normalizeHost(rawHost)
        guard host != serverHost else { return }
        serverHost = host
        UserDefaults.standard.set(host, forKey: AppConfig.serverHostDefaultsKey)
        resetLoadedState()
        needsReauth = false
        hasToken = Keychain.hasToken(for: host)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLogin = LaunchAtLogin.set(enabled)
    }

    // MARK: - Token management

    /// Validate and store a pasted token for the currently selected server.
    /// The server judges validity (via `GET /me`); we store only on 200.
    func connect(token raw: String) async -> Bool {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            errorMessage = "Paste a token first."
            return false
        }
        guard token.hasPrefix(AppConfig.tokenPrefix) else {
            errorMessage = "That doesn't look like a personal access token (they start with \(AppConfig.tokenPrefix))."
            return false
        }
        guard let baseURL = Server.baseURL(host: serverHost) else {
            errorMessage = "Couldn't build a URL for \(selectedServer.name)."
            return false
        }

        isLoading = true
        defer { isLoading = false }

        let client = APIClient(baseURL: baseURL, token: token)
        do {
            let me = try await client.me()
            guard Keychain.setToken(token, for: serverHost) else {
                errorMessage = "Couldn't save the token to the Keychain."
                return false
            }
            setTokenPrefix(String(token.prefix(12)), for: serverHost)
            self.me = me
            self.cachedToken = token   // seed the cache so loads don't re-read
            self.hasToken = true
            self.needsReauth = false
            self.editingServers = false
            self.errorMessage = nil
            refreshTokenStatus()
            await loadEverything()
            return true
        } catch APIError.unauthorized {
            errorMessage = "\(selectedServer.name) rejected that token — it may be wrong or revoked."
            return false
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    /// Remove the current server's token (leaves other servers untouched).
    func signOut() {
        removeToken(for: serverHost)
    }

    // MARK: - Loading

    /// Fetch identity, periods, and the current period's timesheet.
    func loadEverything() async {
        guard let client = makeClient() else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let meResult = client.me()
            async let periodsResult = client.periods()
            self.me = try await meResult
            let periods = try await periodsResult
            self.periods = periods

            if let current = periods.first(where: { $0.isCurrent }) ?? periods.first {
                self.timesheet = try await client.timesheet(periodID: current.id)
            } else {
                self.timesheet = nil
            }
            self.lastRefreshed = Date()
        } catch {
            handle(error)
        }
    }

    /// Load a specific period's timesheet (e.g. user picked a different one).
    func loadTimesheet(periodID: Int) async {
        guard let client = makeClient() else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            self.timesheet = try await client.timesheet(periodID: periodID)
            self.lastRefreshed = Date()
        } catch {
            handle(error)
        }
    }

    // MARK: - Editing

    /// Save a day's edits. The server returns the refreshed card which we adopt.
    func saveDay(_ update: DayUpdate) async -> Bool {
        guard let client = makeClient(), let ts = timesheet else { return false }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            self.timesheet = try await client.updateDay(periodID: ts.id, update: update)
            self.lastRefreshed = Date()
            return true
        } catch {
            handle(error)
            return false
        }
    }

    /// Submit the current timesheet. Returns nil on success, or the blocking
    /// message on a 409 / other failure.
    func submit() async -> String? {
        guard let client = makeClient(), let ts = timesheet else { return "Nothing to submit." }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            self.timesheet = try await client.submit(periodID: ts.id)
            self.lastRefreshed = Date()
            return nil
        } catch APIError.conflict(let message) {
            return message
        } catch {
            handle(error)
            return (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func makeClient() -> APIClient? {
        // Prefer the in-memory copy; only touch the Keychain (which may prompt)
        // if we haven't read it yet this launch.
        guard let baseURL = Server.baseURL(host: serverHost),
              let token = cachedToken ?? Keychain.token(for: serverHost) else {
            hasToken = false
            needsReauth = true
            return nil
        }
        cachedToken = token
        return APIClient(baseURL: baseURL, token: token)
    }

    private func handle(_ error: Error) {
        if case APIError.unauthorized = error {
            cachedToken = nil   // stored token is bad; force a fresh read/paste
            needsReauth = true
            hasToken = false
            errorMessage = APIError.unauthorized.errorDescription
        } else {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func resetLoadedState() {
        cachedToken = nil   // different server → different token
        me = nil
        periods = []
        timesheet = nil
        errorMessage = nil
        lastRefreshed = nil
    }

    // MARK: - Derived display helpers

    var currentPeriod: Period? {
        periods.first(where: { $0.isCurrent }) ?? periods.first
    }

    /// Human-readable "you can submit after…" message, or nil if submittable now.
    var submitBlockedMessage: String? {
        guard let raw = timesheet?.submitBlockedUntil, !raw.isEmpty else { return nil }
        return raw
    }

    var canSubmit: Bool {
        guard let ts = timesheet, ts.editable else { return false }
        if ts.status.lowercased() == "submitted" { return false }
        return submitBlockedMessage == nil
    }

    /// True when the current period still needs attention (an active, editable
    /// sheet past its submit lock) — used to nudge via the menu bar icon.
    var currentPeriodNeedsAction: Bool {
        guard let ts = timesheet, ts.id == currentPeriod?.id, ts.editable else { return false }
        let status = StatusLabel.normalized(ts.status)
        guard status == "draft" || status == "in-progress" else { return false }
        return submitBlockedMessage == nil
    }

    /// SF Symbol shown in the menu bar. Switches to a nudge when action's due.
    var menuBarSymbol: String {
        currentPeriodNeedsAction ? "clock.badge.exclamationmark" : "clock.badge.checkmark"
    }
}
