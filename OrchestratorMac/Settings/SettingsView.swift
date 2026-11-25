import OrchestratorKit
import SwiftUI

/// Account, SSH user, refresh intervals, notification kinds, open at login.
struct SettingsView: View {
    let environment: AppEnvironment

    /// Fixed: a tab view of grouped forms must not size its window (see `WindowCoordinator`).
    static let size = NSSize(width: 500, height: 520)

    var body: some View {
        TabView {
            GeneralSettingsView(environment: environment, settings: environment.settings)
                .tabItem { Label("General", systemImage: "gearshape") }
            NotificationSettingsView(settings: environment.settings)
                .tabItem { Label("Notifications", systemImage: "bell") }
            AccountSettingsView(environment: environment)
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }
}

private struct GeneralSettingsView: View {
    let environment: AppEnvironment
    @Bindable var settings: AppSettings
    @State private var launchAtLogin = LaunchAtLogin()

    var body: some View {
        Form {
            Section {
                TextField("SSH user for \(APIConfig.baseURL.host() ?? "the panel server")", text: $settings.localSSHUser)
            } footer: {
                Text("SSH opens Terminal with your own keys. Remote servers use the user stored in the panel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Open at login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.set($0) }
                ))
                if launchAtLogin.needsApproval {
                    HStack {
                        Text("Allow Orchestrator under Login Items in System Settings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Open") { launchAtLogin.openSystemSettings() }
                            .buttonStyle(.link)
                    }
                }
                if let error = launchAtLogin.errorMessage {
                    Text(error).font(.caption).foregroundStyle(Color.statusDangerText)
                }
            }

            Section {
                Picker("While the popover is open", selection: $settings.fastRefreshSeconds) {
                    ForEach(AppSettings.fastChoices, id: \.self) { Text(Self.label($0)).tag($0) }
                }
                Picker("In the background", selection: $settings.backgroundRefreshSeconds) {
                    ForEach(AppSettings.backgroundChoices, id: \.self) { Text(Self.label($0)).tag($0) }
                }
                Picker("Site list and deploys", selection: $settings.siteListRefreshSeconds) {
                    ForEach(AppSettings.siteListChoices, id: \.self) { Text(Self.label($0)).tag($0) }
                }
            } header: {
                Text("Refresh")
            } footer: {
                Text("Refreshing pauses while the Mac sleeps or is offline. The site list carries each site's last deploy log, so it refreshes less often.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { launchAtLogin.refresh() }

    }

    private static func label(_ seconds: Int) -> String {
        seconds < 60 ? "Every \(seconds) seconds" : (seconds == 60 ? "Every minute" : "Every \(seconds / 60) minutes")
    }
}

private struct NotificationSettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle("Deploy results", isOn: $settings.notifyDeploys)
                Toggle("Server alerts (disk, CPU, RAM, offline)", isOn: $settings.notifyServerAlerts)
                Toggle("Certificates expiring within \(AppSettings.sslWarningDays) days", isOn: $settings.notifyCertificates)
            } footer: {
                HStack(spacing: 4) {
                    Text("Banner style and sounds are set in System Settings.")
                    Button("Open") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.link)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AccountSettingsView: View {
    let environment: AppEnvironment

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
    @State private var confirmingSignOut = false

    private var session: Session { environment.session }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 48, height: 48)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Orchestrator").font(.headline)
                        Text("Version \(Self.version)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                LabeledContent("Panel", value: APIConfig.baseURL.host() ?? APIConfig.baseURL.absoluteString)
                switch session.phase {
                case .signedIn:
                    LabeledContent("Account", value: session.user?.email ?? "—")
                    LabeledContent("Role", value: session.user?.role?.capitalized ?? "—")
                    LabeledContent("Credential", value: session.tokenKind?.displayName ?? "—")
                case .signedOut, .launching:
                    LabeledContent("Account", value: "Signed out")
                }
            } footer: {
                Text("The token is stored in this Mac's login keychain and used only by this app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                if session.phase == .signedIn {
                    Button("Sign Out…", role: .destructive) { confirmingSignOut = true }
                } else {
                    Button("Sign In…") { environment.windows.showSignIn() }
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Sign out of Orchestrator?", isPresented: $confirmingSignOut) {
            Button("Sign Out", role: .destructive) { environment.signOut() }
        } message: {
            Text("The token is removed from this Mac's Keychain. Nothing changes in the panel.")
        }
    }
}
