import SwiftUI

struct SettingsView: View {
    @Environment(Session.self) private var session
    @Environment(AppLock.self) private var appLock
    @Environment(\.dismiss) private var dismiss

    @State private var tokens: [APIToken] = []
    @State private var tokensError: String?
    @State private var showsSignOutConfirmation = false
    @State private var lockError: String?
    @State private var isTogglingLock = false

    /// `true` when pushed onto an existing navigation stack.
    var embedded = false

    var body: some View {
        if embedded {
            screen
        } else {
            NavigationStack { screen }
        }
    }

    private var screen: some View {
        List {
                Section("Account") {
                    HStack {
                        Text(session.user?.initials ?? "?")
                            .font(.headline)
                            .frame(width: 40, height: 40)
                            .background(Color.accentColor.opacity(0.15), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.user?.email ?? "—")
                                .font(.callout.weight(.medium))
                            Text(session.user?.role?.capitalized ?? "—")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Text("Two-factor")
                        Spacer()
                        StatusBadge(
                            session.user?.totpEnabled == true ? "enabled" : "off",
                            tone: session.user?.totpEnabled == true ? .good : .neutral
                        )
                    }
                }

                Section {
                    Toggle(isOn: Binding(
                        get: { appLock.isEnabled },
                        set: { enabled in Task { await toggleLock(enabled) } }
                    )) {
                        HStack(spacing: 10) {
                            Image(systemName: appLock.symbol)
                                .foregroundStyle(.tint)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Require \(appLock.unlockMethodDescription)")
                                if isTogglingLock {
                                    Text("Updating the Keychain item…")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .disabled(isTogglingLock || !appLock.canAuthenticate)

                    if let lockError {
                        Text(lockError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("App lock")
                } footer: {
                    if !appLock.canAuthenticate {
                        Text("Set a passcode on this device to enable the app lock.")
                    } else if appLock.isEnabled {
                        Text("The API token is sealed with a Keychain access-control rule, so iOS itself will not release it without \(appLock.unlockMethodDescription). The app re-locks after a minute in the background.")
                    } else {
                        Text("Turning this on re-writes the token so that iOS will only release it after \(appLock.unlockMethodDescription). The app then re-locks after a minute in the background.")
                    }
                }

                Section {
                    DetailRow(label: "Server", value: APIConfig.baseURL.host(), monospaced: true)
                    DetailRow(label: "Credential", value: session.tokenKind?.displayName)
                } header: {
                    Text("Connection")
                } footer: {
                    Text("The token is stored in the iOS Keychain and is never written to logs or to this app's preferences.")
                }

                Section {
                    if let tokensError {
                        Text(tokensError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if tokens.isEmpty {
                        Text("No personal access tokens.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(tokens) { token in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(token.name)
                                    .font(.callout)
                                HStack(spacing: 8) {
                                    if let prefix = token.tokenPrefix {
                                        Text("\(prefix)…")
                                            .font(.caption2.monospaced())
                                    }
                                    Text("last used \(token.lastUsedAt.relativeShortOrDash)")
                                        .font(.caption2)
                                }
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("API tokens")
                } footer: {
                    Text("Read-only in this phase. Creating and revoking tokens arrives with the settings phase.")
                }

                Section {
                    Button("Sign out", role: .destructive) {
                        showsSignOutConfirmation = true
                    }
                }
            }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(embedded ? .inline : .large)
        .toolbar {
            if !embedded {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await loadTokens() }
            .refreshable { await loadTokens() }
            .confirmationDialog(
                "Sign out of Orchestrator?",
                isPresented: $showsSignOutConfirmation,
                titleVisibility: .visible
            ) {
                Button("Sign out", role: .destructive) { session.signOut() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The token will be removed from this device's Keychain. It stays valid in the panel.")
            }
    }

    private func toggleLock(_ enabled: Bool) async {
        isTogglingLock = true
        lockError = nil
        defer { isTogglingLock = false }
        do {
            if enabled { try await appLock.enable() } else { try await appLock.disable() }
        } catch {
            lockError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func loadTokens() async {
        do {
            tokens = try await OrchestratorAPI.shared.tokens()
            tokensError = nil
        } catch {
            tokensError = APIError.wrap(error).errorDescription
        }
    }
}
