import SwiftUI
import OrchestratorKit

struct LoginView: View {
    @Environment(Session.self) private var session

    @State private var token = ""
    @State private var showsPasswordLogin = false
    @FocusState private var tokenFieldFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Personal access token")
                            .font(.subheadline.weight(.semibold))

                        SecureField("orch_…", text: $token)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.go)
                            .focused($tokenFieldFocused)
                            .onSubmit { submitToken() }

                        Text("Create one in the panel under Settings → API tokens. It is stored in the iOS Keychain and never leaves this device.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let error = session.signInError {
                        InlineErrorBanner(message: error)
                    }

                    VStack(spacing: 10) {
                        Button {
                            submitToken()
                        } label: {
                            if session.isWorking {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else {
                                Text("Connect")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(session.isWorking || token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        if session.hasStoredToken {
                            Button("Retry with saved token") {
                                Task { await session.retryStoredToken() }
                            }
                            .disabled(session.isWorking)
                        }

                        Button("Sign in with email instead") {
                            showsPasswordLogin = true
                        }
                        .font(.footnote)
                        .disabled(session.isWorking)
                    }

                    serverFooter
                }
                .padding(24)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Orchestrator")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showsPasswordLogin) {
                PasswordLoginView()
            }
            .onAppear { tokenFieldFocused = !session.hasStoredToken }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            OrchestratorLogo(size: 72)
            Text("Connect to your panel")
                .font(.title2.weight(.semibold))
            Text("Sites, deploys, monitoring and billing — natively.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 24)
    }

    private var serverFooter: some View {
        VStack(spacing: 4) {
            Text(APIConfig.baseURL.host() ?? APIConfig.baseURL.absoluteString)
                .font(.caption.monospaced())
            Text("TLS via Let's Encrypt")
                .font(.caption2)
        }
        .foregroundStyle(.secondary)
        .padding(.top, 8)
    }

    private func submitToken() {
        tokenFieldFocused = false
        Task {
            await session.signIn(personalAccessToken: token)
            if session.phase == .signedIn { token = "" }
        }
    }
}

struct PasswordLoginView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var totpCode = ""
    @State private var needsTOTP = false
    @State private var errorMessage: String?
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                }

                if needsTOTP {
                    Section {
                        TextField("6-digit code", text: $totpCode)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                    } header: {
                        Text("Two-factor authentication")
                    } footer: {
                        Text("Enter the code from your authenticator app.")
                    }
                }

                if let errorMessage {
                    Section {
                        InlineErrorBanner(message: errorMessage)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }

                Section {
                    Button {
                        submit()
                    } label: {
                        HStack {
                            Spacer()
                            if isSubmitting { ProgressView() } else { Text("Sign in") }
                            Spacer()
                        }
                    }
                    .disabled(isSubmitting || email.isEmpty || password.isEmpty || (needsTOTP && totpCode.count < 6))
                } footer: {
                    Text("A JWT session is shorter-lived than a personal access token. For day-to-day use prefer a token.")
                }
            }
            .navigationTitle("Email sign-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func submit() {
        isSubmitting = true
        errorMessage = nil
        Task {
            defer { isSubmitting = false }
            do {
                let result = try await session.signIn(
                    email: email,
                    password: password,
                    totpCode: needsTOTP ? totpCode : nil
                )
                switch result {
                case .signedIn:
                    dismiss()
                case .requiresTOTP:
                    needsTOTP = true
                    errorMessage = nil
                }
            } catch {
                errorMessage = APIError.wrap(error).errorDescription
            }
        }
    }
}

#Preview {
    LoginView()
        .environment(Session())
}
