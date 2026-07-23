import SwiftUI
import AppKit

/// Top-level router for the menu bar window. Decides between the token-entry
/// screen and the main timesheet screen, and hosts the shared footer.
struct RootView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar()
            Divider()

            Group {
                if !state.hasToken || state.needsReauth || state.changingServer {
                    TokenEntryView()
                } else if state.editingDefaults {
                    DefaultsEditView()
                } else {
                    TimesheetView()
                }
            }
            .frame(maxWidth: .infinity)

            Divider()
            FooterBar()
        }
        .task {
            // On first appearance, load data if we already have a token.
            if state.hasToken && !state.needsReauth && state.timesheet == nil {
                await state.loadEverything()
            }
        }
        .onAppear {
            // Catch a day rollover the instant the menu opens.
            state.tick()
        }
    }
}

/// App title.
private struct HeaderBar: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.badge.checkmark")
                .foregroundStyle(.tint)
            Text("Time Sheets")
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

/// Footer: refresh, settings, and quit.
private struct FooterBar: View {
    @EnvironmentObject private var state: AppState

    /// "Show all timesheets", annotated with how many are currently hidden.
    private var showAllPeriodsLabel: String {
        let hidden = state.hiddenCompletedCount
        return hidden > 0 ? "Show all timesheets (\(hidden) hidden)" : "Show all timesheets"
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(AppConfig.appVersion)
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let refreshed = state.lastRefreshed {
                Text("Updated \(DateParsing.relativeTime(refreshed))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            Menu {
                Toggle("Show weekends", isOn: $state.showWeekends)
                Toggle(showAllPeriodsLabel, isOn: $state.showAllPeriods)
                Toggle("Launch at login", isOn: Binding(
                    get: { state.launchAtLogin },
                    set: { state.setLaunchAtLogin($0) }
                ))
                if state.hasToken {
                    Divider()
                    Button("Default hours…") { state.beginEditingDefaults() }
                }
                Divider()
                Section(state.serverHost) {
                    if let web = Server.webURL(host: state.serverHost) {
                        Link("Open Time Sheets website", destination: web)
                    }
                    Button("Change server…") { state.beginChangingServer() }
                }
                if state.hasToken {
                    Divider()
                    Button("Sign out", role: .destructive) {
                        state.signOut()
                    }
                }
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button {
                Task { await state.loadEverything() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(!state.hasToken || state.isLoading)
            .help("Refresh")

            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
