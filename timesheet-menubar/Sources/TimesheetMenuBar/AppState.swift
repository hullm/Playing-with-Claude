import Foundation
import SwiftUI

/// Central observable state for the menu bar UI.
///
/// Owns the selected environment + token, and drives all API traffic. Views
/// observe this and call its `async` action methods.
@MainActor
final class AppState: ObservableObject {

    // Configuration
    @Published var environment: ServerEnvironment {
        didSet {
            UserDefaults.standard.set(environment.rawValue, forKey: AppConfig.environmentDefaultsKey)
            // Environment changed → drop loaded data and re-check for a token.
            resetLoadedState()
            hasToken = Keychain.token(for: environment) != nil
        }
    }
    @Published private(set) var hasToken: Bool
    @Published var launchAtLogin: Bool

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
        let raw = UserDefaults.standard.string(forKey: AppConfig.environmentDefaultsKey)
        let env = raw.flatMap(ServerEnvironment.init(rawValue:)) ?? .dev
        self.environment = env
        self.hasToken = Keychain.token(for: env) != nil
        self.launchAtLogin = LaunchAtLogin.isEnabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLogin = LaunchAtLogin.set(enabled)
    }

    // MARK: - Token management

    /// Validate and store a pasted token. Returns true if the token works.
    func saveAndVerifyToken(_ raw: String) async -> Bool {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            errorMessage = "Paste a token first."
            return false
        }
        guard token.hasPrefix(AppConfig.tokenPrefix) else {
            errorMessage = "That doesn't look like a personal access token (they start with \(AppConfig.tokenPrefix))."
            return false
        }

        isLoading = true
        defer { isLoading = false }

        let client = APIClient(environment: environment, token: token)
        do {
            let me = try await client.me()
            guard Keychain.setToken(token, for: environment) else {
                errorMessage = "Couldn't save the token to the Keychain."
                return false
            }
            self.me = me
            self.hasToken = true
            self.needsReauth = false
            self.errorMessage = nil
            await loadEverything()
            return true
        } catch APIError.unauthorized {
            errorMessage = "That token was rejected. Double-check you copied the whole thing."
            return false
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    func signOut() {
        Keychain.deleteToken(for: environment)
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
        guard let token = Keychain.token(for: environment) else {
            hasToken = false
            needsReauth = true
            return nil
        }
        return APIClient(environment: environment, token: token)
    }

    private func handle(_ error: Error) {
        if case APIError.unauthorized = error {
            needsReauth = true
            hasToken = false
            errorMessage = APIError.unauthorized.errorDescription
        } else {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func resetLoadedState() {
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

    /// True when the current period still needs attention (draft, editable, and
    /// past its submit lock) — used to nudge via the menu bar icon.
    var currentPeriodNeedsAction: Bool {
        guard let ts = timesheet, ts.id == currentPeriod?.id,
              ts.editable, ts.status.lowercased() == "draft" else { return false }
        return submitBlockedMessage == nil
    }

    /// SF Symbol shown in the menu bar. Switches to a nudge when action's due.
    var menuBarSymbol: String {
        currentPeriodNeedsAction ? "clock.badge.exclamationmark" : "clock.badge.checkmark"
    }
}
