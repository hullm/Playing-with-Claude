import SwiftUI

/// Screen shown when there's no stored token, or after a 401.
struct TokenEntryView: View {
    @EnvironmentObject private var state: AppState
    @State private var token = ""
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if state.needsReauth {
                Label("Your token was rejected. Paste a fresh one.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            } else {
                HStack(spacing: 6) {
                    Text("Connect your account")
                        .font(.headline)
                    Text("(\(state.environment.label))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Generate a personal access token in the web app under **Settings → API access**, then paste it here. It's stored only in your macOS Keychain.")
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

            HStack {
                Link("Open web app", destination: state.environment.baseURL
                    .deletingLastPathComponent()   // strip /v1
                    .deletingLastPathComponent())  // strip /api
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
    }

    private func save() {
        guard !working else { return }
        working = true
        Task {
            _ = await state.saveAndVerifyToken(token)
            working = false
        }
    }
}
