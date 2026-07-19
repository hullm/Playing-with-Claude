import SwiftUI

/// Screen shown when there's no stored token, after a 401, or when the user
/// chooses to change the server. Lets them set the server and paste a token.
struct TokenEntryView: View {
    @EnvironmentObject private var state: AppState
    @State private var server = ""
    @State private var token = ""
    @State private var working = false

    /// True when this is a deliberate server change while already signed in
    /// (so we can offer a Cancel button).
    private var canCancel: Bool { state.changingServer && state.hasToken }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if state.needsReauth {
                Label("Your token was rejected. Paste a fresh one.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            } else {
                Text(state.changingServer ? "Change server" : "Connect your account")
                    .font(.headline)
            }

            Text("Enter your Time Sheets server, then paste a personal access token from the web app under **Settings → API access**. The token is stored only in your macOS Keychain.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Server").font(.caption).foregroundStyle(.secondary)
                TextField("timesheets.lkgeorge.org", text: $server)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled(true)
                    .onSubmit(save)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Access token").font(.caption).foregroundStyle(.secondary)
                SecureField("tsk_…", text: $token)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(save)
            }

            if let error = state.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if let web = Server.webURL(host: server.isEmpty ? state.serverHost : server) {
                    Link("Open web app", destination: web).font(.caption)
                }
                Spacer()
                if canCancel {
                    Button("Cancel") { state.cancelChangingServer() }
                        .keyboardShortcut(.cancelAction)
                }
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
                .disabled(!canSubmit || working)
            }
        }
        .padding(12)
        .onAppear {
            if server.isEmpty { server = state.serverHost }
        }
    }

    private var canSubmit: Bool {
        !server.trimmingCharacters(in: .whitespaces).isEmpty
        && !token.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func save() {
        guard !working, canSubmit else { return }
        working = true
        Task {
            _ = await state.connect(server: server, token: token)
            working = false
        }
    }
}
