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
                if !state.hasToken || state.needsReauth {
                    TokenEntryView()
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
    }
}

/// Title + environment badge.
private struct HeaderBar: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.badge.checkmark")
                .foregroundStyle(.tint)
            Text("Time Sheets")
                .font(.headline)
            Spacer()
            EnvironmentBadge(environment: state.environment)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

private struct EnvironmentBadge: View {
    let environment: ServerEnvironment
    var body: some View {
        Text(environment.shortLabel)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(environment == .prod ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
            .foregroundStyle(environment == .prod ? .green : .orange)
            .clipShape(Capsule())
    }
}

/// Footer: refresh, environment switch, and quit.
private struct FooterBar: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        HStack(spacing: 12) {
            if let refreshed = state.lastRefreshed {
                Text("Updated \(DateParsing.relativeTime(refreshed))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            Menu {
                Toggle("Launch at login", isOn: Binding(
                    get: { state.launchAtLogin },
                    set: { state.setLaunchAtLogin($0) }
                ))
                Divider()
                Picker("Server", selection: Binding(
                    get: { state.environment },
                    set: { state.environment = $0 }
                )) {
                    ForEach(ServerEnvironment.allCases) { env in
                        Text(env.label).tag(env)
                    }
                }
                if state.hasToken {
                    Divider()
                    Button("Sign out of \(state.environment.label)", role: .destructive) {
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
