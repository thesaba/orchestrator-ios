import OrchestratorKit
import SwiftUI

/// Who can open the site: an nginx password prompt (basic auth) and address rules. This is
/// what the panel offers for a site's security; applying asks for Touch ID.
struct SiteSecurityTab: View {
    let environment: AppEnvironment
    var row: SiteTableRow

    @State private var current: SiteSecurity?
    @State private var error: String?
    @State private var basicAuth = false
    @State private var user = ""
    @State private var password = ""
    @State private var ipMode = "off"
    @State private var ipText = ""
    @State private var isSaving = false

    private var ipList: [String] {
        ipText.split(whereSeparator: { $0.isNewline || $0 == "," || $0 == " " }).map(String.init)
    }

    private var isEdited: Bool {
        guard let current else { return false }
        return basicAuth != current.basicAuth || user != (current.basicUser ?? "") || !password.isEmpty
            || ipMode != (current.ipMode ?? "off") || ipList != current.ipList
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Color.statusDangerText)
                }
                summary
                HStack(alignment: .top, spacing: 16) {
                    passwordCard.frame(maxWidth: .infinity, alignment: .topLeading)
                    addressCard.frame(maxWidth: .infinity, alignment: .topLeading)
                }
                HStack {
                    Text("Changes reload nginx. If nginx rejects the new config, nothing is applied.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Revert") { apply(current) }
                        .disabled(!isEdited || isSaving)
                    Button("Apply…") { save() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!isEdited || isSaving || (basicAuth && user.isEmpty) || (basicAuth && current?.hasPassword != true && password.isEmpty))
                }
                .controlSize(.small)
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .task(id: row.id) { await load() }
    }

    private func load() async {
        do {
            let value = try await environment.api.security(siteID: row.id)
            apply(value)
            error = nil
        } catch {
            self.error = APIError.wrap(error).errorDescription
        }
    }

    private func apply(_ value: SiteSecurity?) {
        guard let value else { return }
        current = value
        basicAuth = value.basicAuth
        user = value.basicUser ?? ""
        password = ""
        ipMode = value.ipMode ?? "off"
        ipText = value.ipList.joined(separator: "\n")
    }

    private var summary: some View {
        HStack(spacing: 12) {
            Image(systemName: isOpen ? "lock.open" : "lock.fill")
                .font(.system(size: 22))
                .foregroundStyle(isOpen ? Color.secondary : Color.accentText)
                .frame(width: 40)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(isOpen ? "\(row.domain) is open to everyone" : "\(row.domain) is restricted")
                    .font(.system(size: 15, weight: .semibold))
                Text(summaryDetail).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .card(tint: isOpen ? nil : .tintInfo)
    }

    private var isOpen: Bool { !(current?.basicAuth ?? false) && (current?.ipMode ?? "off") == "off" }

    private var summaryDetail: String {
        guard let current else { return "Loading…" }
        var parts: [String] = []
        parts.append(current.basicAuth ? "Password prompt for \(current.basicUser ?? "a user")" : "No password prompt")
        switch current.ipMode {
        case "allow"?: parts.append("only \(current.ipList.count) address\(current.ipList.count == 1 ? "" : "es") allowed")
        case "deny"?:  parts.append("\(current.ipList.count) address\(current.ipList.count == 1 ? "" : "es") blocked")
        default:       parts.append("no address rules")
        }
        if row.isStaging, isOpen { parts.append("a staging copy is usually better behind a password") }
        return parts.joined(separator: " · ")
    }

    private var passwordCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Password prompt", symbol: "person.badge.key.fill", tint: Vivid.orange)
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Ask visitors for a user name and password", isOn: $basicAuth)
                    .font(.system(size: 12))
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                    GridRow {
                        Text("User").font(.system(size: 12)).foregroundStyle(.secondary)
                        TextField("User name", text: $user).textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("Password").font(.system(size: 12)).foregroundStyle(.secondary)
                        SecureField(current?.hasPassword == true ? "Unchanged" : "New password", text: $password)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .disabled(!basicAuth)
                Text("Applies to the whole site, the panel’s health checks included. The password is stored hashed; it can’t be shown again.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .card()
        }
    }

    private var addressCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Address rules", symbol: "network.badge.shield.half.filled", tint: Vivid.teal)
            VStack(alignment: .leading, spacing: 10) {
                Picker("Rule", selection: $ipMode) {
                    Text("Off").tag("off")
                    Text("Allow only these").tag("allow")
                    Text("Block these").tag("deny")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                TextEditor(text: $ipText)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .background(Color.logGround)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .frame(height: 110)
                    .disabled(ipMode == "off")
                    .accessibilityLabel("IP addresses, one per line")
                Text("One IPv4 or IPv6 address or CIDR range per line, up to 100.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .card()
        }
    }

    private func save() {
        guard let current else { return }
        let list = ipMode == "off" ? [] : ipList
        isSaving = true
        Task {
            defer { isSaving = false }
            if let updated = await environment.executor.updateSecurity(
                siteID: row.id, current: current, basicAuth: basicAuth, user: user, password: password,
                ipMode: ipMode, ipList: list) {
                apply(updated)
            }
        }
    }
}
