import SwiftUI

/// Manage servers: see which one is active and which have a token, switch
/// between them (reusing stored tokens), add/remove custom servers, and remove a
/// single server's token. The token itself is never shown after it's saved.
struct ServersView: View {
    @EnvironmentObject private var state: AppState
    @State private var showAdd = false
    @State private var newName = ""
    @State private var newHost = ""
    @State private var addError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(state.knownServers) { server in
                        ServerRow(server: server)
                        Divider()
                    }
                }
            }
            .frame(maxHeight: 240)

            addSection
        }
        .padding(12)
    }

    private var header: some View {
        HStack {
            Button(action: { state.cancelEditingServers() }) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            Text("Servers").font(.headline)
            Spacer()
        }
    }

    @ViewBuilder private var addSection: some View {
        if showAdd {
            VStack(alignment: .leading, spacing: 6) {
                TextField("Name (optional)", text: $newName)
                    .textFieldStyle(.roundedBorder)
                TextField("host, e.g. timesheets.example.org", text: $newHost)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled(true)
                    .onSubmit(add)
                if let addError {
                    Text(addError).font(.caption).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Button("Cancel") { reset() }
                    Spacer()
                    Button("Add", action: add)
                        .buttonStyle(.borderedProminent)
                        .disabled(newHost.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        } else {
            Button { showAdd = true } label: {
                Label("Add server…", systemImage: "plus")
            }
            .buttonStyle(.borderless)
        }
    }

    private func add() {
        addError = state.addCustomServer(name: newName, host: newHost)
        if addError == nil { reset() } // addCustomServer selects it and closes the screen
    }

    private func reset() {
        showAdd = false; newName = ""; newHost = ""; addError = nil
    }
}

/// One server row: name + badge, token status, active check, and an actions menu.
private struct ServerRow: View {
    @EnvironmentObject private var state: AppState
    let server: ServerInfo

    private var isActive: Bool { server.host == state.serverHost }
    private var hasToken: Bool { state.serversWithToken.contains(server.host) }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(server.name).font(.callout.weight(.medium))
                    ServerBadge(server: server)
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(hasToken ? Color.secondary : Color.orange)
            }
            Spacer()
            if isActive {
                Image(systemName: "checkmark").foregroundStyle(.tint)
            }
            Menu {
                if !isActive {
                    Button("Switch to this server") { state.selectServer(server.host) }
                } else if !hasToken {
                    Button("Add token") { state.cancelEditingServers() }
                }
                if hasToken {
                    Button("Remove token", role: .destructive) {
                        state.removeToken(for: server.host)
                    }
                }
                if !server.isBuiltIn {
                    Button("Remove server", role: .destructive) {
                        state.removeCustomServer(server.host)
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isActive { state.selectServer(server.host) }
            else if !hasToken { state.cancelEditingServers() }
        }
    }

    private var subtitle: String {
        guard hasToken else { return "No token — tap to add" }
        return state.tokenPrefix(for: server.host).map { "Token \($0)…" } ?? "Token saved"
    }
}
