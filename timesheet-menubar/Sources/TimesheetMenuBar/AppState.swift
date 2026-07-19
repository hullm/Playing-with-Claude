import Foundation
import SwiftUI

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
    /// When true, force the connect screen so the user can edit the server/token.
    @Published var changingServer = false
    /// When true, show the default-hours editor.
    @Published var editingDefaults = false

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

    init() {
        let host = UserDefaults.standard.string(forKey: AppConfig.serverHostDefaultsKey)
            ?? AppConfig.defaultServerHost
        self.serverHost = host
        self.hasToken = Keychain.hasToken(for: host)
        self.launchAtLogin = LaunchAtLogin.isEnabled
        self.showWeekends = UserDefaults.standard.bool(forKey: AppConfig.showWeekendsDefaultsKey)
        self.showAllPeriods = UserDefaults.standard.bool(forKey: AppConfig.showAllPeriodsDefaultsKey)
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

    /// Switch to the connect screen so the user can change the server.
    func beginChangingServer() {
        errorMessage = nil
        changingServer = true
    }

    /// Cancel an in-progress server change (only meaningful when already signed in).
    func cancelChangingServer() {
        errorMessage = nil
        changingServer = false
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
        hasToken = Keychain.hasToken(for: host)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLogin = LaunchAtLogin.set(enabled)
    }

    // MARK: - Token management

    /// Set the server and validate/store a pasted token. Returns true on success.
    func connect(server rawHost: String, token raw: String) async -> Bool {
        guard Server.isValidHost(rawHost) else {
            errorMessage = "Enter a valid server name, like timesheets.lkgeorge.org."
            return false
        }
        applyServerHost(rawHost)

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
            errorMessage = "Couldn't build a URL for that server."
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
            self.me = me
            self.cachedToken = token   // seed the cache so loads don't re-read
            self.hasToken = true
            self.needsReauth = false
            self.changingServer = false
            self.errorMessage = nil
            await loadEverything()
            return true
        } catch APIError.unauthorized {
            errorMessage = "That token was rejected for \(serverHost). Double-check the server and that you copied the whole token."
            return false
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    func signOut() {
        Keychain.deleteToken(for: serverHost)
        cachedToken = nil
        hasToken = false
        resetLoadedState()
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
