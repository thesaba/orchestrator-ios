import OrchestratorKit
import SwiftUI

/// Personal access token sign-in. The token goes straight to the shared Keychain item.
struct SignInView: View {
    let session: Session
    @State private var token = ""
    @FocusState private var tokenFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                OrchestratorLogo(size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sign in to Orchestrator")
                        .font(.headline)
                    Text(APIConfig.baseURL.host() ?? APIConfig.baseURL.absoluteString)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                SecureField("Personal access token", text: $token, prompt: Text("orch_…"))
                    .textFieldStyle(.roundedBorder)
                    .focused($tokenFocused)
                    .onSubmit(signIn)
                    .accessibilityLabel("Personal access token")
                HStack(spacing: 4) {
                    Text("Create one in the web panel under Settings → API tokens.")
                    Button("Open") { WebPanel.open(.tokens) }
                        .buttonStyle(.link)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let error = session.signInError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.statusDangerText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if session.isWorking {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                Button("Sign In", action: signIn)
                    .keyboardShortcut(.defaultAction)
                    .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || session.isWorking)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear { tokenFocused = true }
    }

    private func signIn() {
        let value = token
        Task {
            await session.signIn(personalAccessToken: value)
            if session.phase == .signedIn { token = "" }
        }
    }
}
