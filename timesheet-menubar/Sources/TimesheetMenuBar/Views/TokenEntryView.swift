import SwiftUI

/// Add-token screen for the currently selected server. Shown when that server
/// has no stored token, or after its token is rejected (401). Scoped to one
/// server — it never touches another server's token.
struct TokenEntryView: View {
    @EnvironmentObject private var state: AppState
    @State private var token = ""
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text(state.needsReauth ? "Token no longer works" : "Add a token")
                    .font(.headline)
                ServerBadge(server: state.selectedServer)
            }

            if state.needsReauth {
                Label("\(state.selectedServer.name) rejected its stored token (wrong or revoked). Paste a fresh one.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Generate a personal access token in **\(state.selectedServer.name)** under **Settings → API access**, then paste it here. Tokens are stored per server in your macOS Keychain.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            SecureField("tsk_…", text: $token)
                .textFieldStyle(.roundedBorder)
                .onSubmit { save() }

            if let error = state.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                if let web = Server.webURL(host: state.serverHost) {
                    Link("Open \(state.selectedServer.name)", destination: web).font(.caption)
                }
                Button("Switch server") { state.beginEditingServers() }
                    .buttonStyle(.borderless)
                    .font(.caption)
                Spacer()
                Button {
                    save()
                } label: {
                    if working {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Connect")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty || working)
            }
        }
        .padding(12)
        .onAppear { token = "" }
    }

    private func save() {
        guard !working else { return }
        working = true
        Task {
            _ = await state.connect(token: token)
            working = false
        }
    }
}
