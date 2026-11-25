import SwiftUI
import OrchestratorKit

struct PHPVersionView: View {
    let site: Site

    @State private var state: LoadState<PHPVersions> = .idle
    @State private var runner = ActionRunner()
    @State private var pending: String?

    var body: some View {
        LoadStateView(
            state: state,
            emptyTitle: "No PHP versions",
            emptyMessage: "The server reported no installed PHP versions.",
            emptyIcon: "chevron.left.forwardslash.chevron.right",
            isEmpty: { $0.available.isEmpty },
            retry: { Task { await load() } }
        ) { versions in
            List {
                Section {
                    ActionFeedbackView(runner: runner)
                        .listRowBackground(Color.clear)
                } footer: {
                    Text("Switching rewrites the site's PHP-FPM pool and reloads nginx. In-flight requests may fail for a moment.")
                }

                Section("Installed") {
                    ForEach(versions.available, id: \.self) { version in
                        Button {
                            guard version != versions.current else { return }
                            pending = version
                        } label: {
                            HStack {
                                Text("PHP \(version)")
                                    .foregroundStyle(.primary)
                                Spacer()
                                if version == versions.current {
                                    StatusBadge("current", tone: .good)
                                } else if runner.isRunning("switch-\(version)") {
                                    ProgressView().controlSize(.small)
                                }
                            }
                        }
                        .disabled(runner.isRunning)
                    }
                }
            }
        }
        .navigationTitle("PHP version")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { if state.value == nil { await load() } }
        .confirmationDialog(
            "Switch \(site.domain) to PHP \(pending ?? "")?",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            titleVisibility: .visible,
            presenting: pending
        ) { version in
            Button("Switch to PHP \(version)", role: .destructive) {
                Task { await switchTo(version) }
            }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: { _ in
            Text("If the application is not compatible with the new version the site can start returning 500s.")
        }
    }

    private func load() async {
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await OrchestratorAPI.shared.phpVersions(siteID: site.id))
        } catch {
            state = .failed(APIError.wrap(error))
        }
    }

    private func switchTo(_ version: String) async {
        pending = nil
        await runner.run("switch-\(version)", success: "Now running PHP \(version).") {
            try await OrchestratorAPI.shared.setPHPVersion(siteID: site.id, version: version)
        } onSuccess: {
            await load()
        }
    }
}

struct SSLManagementView: View {
    let site: Site

    @State private var status: SiteSSL?
    @State private var loadError: APIError?
    @State private var runner = ActionRunner()
    @State private var stream = StreamRunner()
    @State private var confirmation: Kind?

    enum Kind: String, Identifiable {
        case issue, renew, remove
        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ActionFeedbackView(runner: runner)

                SectionCard("Certificate", systemImage: "lock.shield", accessory: AnyView(badge)) {
                    if let status {
                        VStack(alignment: .leading, spacing: 8) {
                            DetailRow(label: "Enabled", value: status.sslEnabled ? "yes" : "no")
                            DetailRow(label: "Active", value: status.active ? "yes" : "no")
                            DetailRow(label: "Expires", value: status.expiresAt.shortDateTimeOrDash)
                            DetailRow(label: "Days left", value: status.daysLeft.map { $0.daysLabel })
                            DetailRow(label: "Issuer", value: status.issuer)
                            if status.running {
                                Label("An issuance is already running.", systemImage: "clock")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                            }
                        }
                    } else if let loadError {
                        InlineErrorBanner(message: loadError.errorDescription ?? "Failed")
                    } else {
                        ProgressView()
                    }
                }

                SectionCard("Actions", systemImage: "bolt") {
                    VStack(spacing: 10) {
                        Button {
                            confirmation = .issue
                        } label: {
                            Label(status?.active == true ? "Re-issue certificate" : "Issue certificate",
                                  systemImage: "checkmark.seal")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            confirmation = .renew
                        } label: {
                            Label("Renew", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button(role: .destructive) {
                            confirmation = .remove
                        } label: {
                            Label("Remove certificate", systemImage: "trash").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .disabled(runner.isRunning || stream.isStreaming)
                }

                if stream.isStreaming || !stream.buffer.lines.isEmpty {
                    SectionCard("Output", systemImage: "terminal") {
                        LogConsoleView(lines: stream.buffer.lines, isStreaming: stream.isStreaming)
                            .frame(height: 260)
                    }
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("SSL")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .onDisappear { stream.stop() }
        .confirmationDialog(
            dialogTitle,
            isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }),
            titleVisibility: .visible,
            presenting: confirmation
        ) { kind in
            switch kind {
            case .issue:  Button("Issue", role: .destructive) { Task { await run(.issue) } }
            case .renew:  Button("Renew") { Task { await run(.renew) } }
            case .remove: Button("Remove certificate", role: .destructive) { Task { await run(.remove) } }
            }
            Button("Cancel", role: .cancel) { confirmation = nil }
        } message: { kind in
            switch kind {
            case .issue:  Text("Let's Encrypt rate-limits issuance to 5 duplicate certificates per week. nginx reloads when it completes.")
            case .renew:  Text("Renews the existing certificate and reloads nginx.")
            case .remove: Text("HTTPS stops working for \(site.domain) immediately.")
            }
        }
    }

    @ViewBuilder
    private var badge: some View {
        if let status {
            StatusBadge(status.active ? "active" : "inactive", tone: status.active ? .good : .neutral)
        }
    }

    private var dialogTitle: String {
        switch confirmation {
        case .issue:  return "Issue a certificate for \(site.domain)?"
        case .renew:  return "Renew \(site.domain)?"
        case .remove: return "Remove the certificate?"
        case nil:     return ""
        }
    }

    private func load() async {
        do {
            status = try await OrchestratorAPI.shared.siteSSL(siteID: site.id)
            loadError = nil
        } catch {
            loadError = APIError.wrap(error)
        }
    }

    private func run(_ kind: Kind) async {
        confirmation = nil
        let siteID = site.id

        if kind != .remove {
            stream.start { OrchestratorAPI.shared.sslStream(siteID: siteID) }
        }

        await runner.run(kind.rawValue, success: successMessage(for: kind)) {
            switch kind {
            case .issue:  try await OrchestratorAPI.shared.issueSSL(siteID: siteID)
            case .renew:  try await OrchestratorAPI.shared.renewSSL(siteID: siteID)
            case .remove: try await OrchestratorAPI.shared.removeSSL(siteID: siteID)
            }
        } onSuccess: {
            await load()
        }

        if runner.errorMessage != nil { stream.stop() }
    }

    private func successMessage(for kind: Kind) -> String {
        switch kind {
        case .issue:  return "Issuance started."
        case .renew:  return "Renewal started."
        case .remove: return "Certificate removed."
        }
    }
}

struct SchedulerView: View {
    let site: Site

    @State private var info: SchedulerInfo?
    @State private var loadError: APIError?
    @State private var runner = ActionRunner()

    var body: some View {
        List {
            Section {
                ActionFeedbackView(runner: runner)
                    .listRowBackground(Color.clear)
            }

            Section {
                if let info {
                    HStack {
                        Text("Scheduler")
                        Spacer()
                        StatusBadge(info.active ? "active" : "off", tone: info.active ? .good : .neutral)
                    }
                    Button(info.active ? "Disable scheduler" : "Enable scheduler",
                           role: info.active ? .destructive : nil) {
                        Task { await toggle(!info.active) }
                    }
                    .disabled(runner.isRunning)
                } else if let loadError {
                    InlineErrorBanner(message: loadError.errorDescription ?? "Failed")
                } else {
                    ProgressView()
                }
            } footer: {
                Text("Installs `php artisan schedule:run` in the server's crontab, once a minute.")
            }

            if let info, !info.currentContent.isEmpty {
                Section("crontab") {
                    Text(info.currentContent)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }

            if let info, let path = info.currentPath {
                Section {
                    DetailRow(label: "Path", value: path, monospaced: true)
                }
            }

            if let expected = info?.expected, !expected.isEmpty {
                Section("Expected entry") {
                    Text(expected)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle("Scheduler")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        do {
            info = try await OrchestratorAPI.shared.scheduler(siteID: site.id)
            loadError = nil
        } catch {
            loadError = APIError.wrap(error)
        }
    }

    private func toggle(_ active: Bool) async {
        await runner.run("scheduler", success: active ? "Scheduler enabled." : "Scheduler disabled.") {
            try await OrchestratorAPI.shared.setScheduler(siteID: site.id, active: active)
        } onSuccess: {
            await load()
        }
    }
}

struct StatusPageView: View {
    let site: Site

    @State private var info: StatusPageInfo?
    @State private var runner = ActionRunner()

    var body: some View {
        List {
            Section {
                ActionFeedbackView(runner: runner)
                    .listRowBackground(Color.clear)
            }

            Section {
                HStack {
                    Text("Public status page")
                    Spacer()
                    StatusBadge(info?.enabled == true ? "public" : "off",
                                tone: info?.enabled == true ? .good : .neutral)
                }
                Button(info?.enabled == true ? "Make private" : "Publish",
                       role: info?.enabled == true ? .destructive : nil) {
                    Task { await toggle(!(info?.enabled ?? false)) }
                }
                .disabled(runner.isRunning || info == nil)
            } footer: {
                Text("A public page shows uptime for this site to anyone holding the link — no login needed.")
            }

            if let url = info?.url, info?.enabled == true, let link = URL(string: url) {
                Section("Link") {
                    Link(destination: link) {
                        Text(url)
                            .font(.caption.monospaced())
                            .lineLimit(2)
                    }
                    ShareLink(item: link) {
                        Label("Share link", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .navigationTitle("Status page")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        info = try? await OrchestratorAPI.shared.statusPage(siteID: site.id)
    }

    private func toggle(_ enabled: Bool) async {
        await runner.run("status-page", success: enabled ? "Status page published." : "Status page is private.") {
            try await OrchestratorAPI.shared.setStatusPage(siteID: site.id, enabled: enabled)
        } onSuccess: {
            await load()
        }
    }
}

struct SiteSecurityView: View {
    let site: Site

    @State private var security: SiteSecurity?
    @State private var basicAuth = false
    @State private var basicUser = ""
    @State private var basicPassword = ""
    @State private var ipMode = "off"
    @State private var ipListText = ""
    @State private var runner = ActionRunner()
    @State private var showsConfirmation = false

    private let ipModes = ["off", "allow", "deny"]

    var body: some View {
        Form {
            Section {
                ActionFeedbackView(runner: runner)
                    .listRowBackground(Color.clear)
            }

            Section {
                Toggle("HTTP basic auth", isOn: $basicAuth)
                if basicAuth {
                    TextField("Username", text: $basicUser)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField(security?.hasPassword == true ? "Password (leave blank to keep)" : "Password",
                                text: $basicPassword)
                }
            } header: {
                Text("Basic auth")
            } footer: {
                Text(security?.hasPassword == true
                     ? "A password is already set. Leave the field blank to keep it."
                     : "Everyone visiting the site will be asked for these credentials.")
            }

            Section {
                Picker("Mode", selection: $ipMode) {
                    Text("Off").tag("off")
                    Text("Allow list").tag("allow")
                    Text("Deny list").tag("deny")
                }
                .pickerStyle(.segmented)

                if ipMode != "off" {
                    TextField("One address or CIDR per line", text: $ipListText, axis: .vertical)
                        .font(.callout.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .lineLimit(3...10)
                }
            } header: {
                Text("IP filter")
            } footer: {
                if ipMode == "allow" {
                    Text("Only these addresses can reach the site. Getting this wrong locks everyone out, including you.")
                        .foregroundStyle(.orange)
                } else if ipMode == "deny" {
                    Text("These addresses are blocked; everyone else is allowed.")
                }
            }

            Section {
                Button("Apply") { showsConfirmation = true }
                    .disabled(runner.isRunning)
            }
        }
        .navigationTitle("Security")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .confirmationDialog(
            "Apply security rules to \(site.domain)?",
            isPresented: $showsConfirmation,
            titleVisibility: .visible
        ) {
            Button("Apply", role: .destructive) { Task { await apply() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(ipMode == "allow"
                 ? "An allow list that omits your own address will lock you out of the site."
                 : "The nginx config for this site is rewritten and reloaded.")
        }
    }

    private func load() async {
        guard let loaded = try? await OrchestratorAPI.shared.security(siteID: site.id) else { return }
        security = loaded
        basicAuth = loaded.basicAuth
        basicUser = loaded.basicUser ?? ""
        ipMode = loaded.ipMode ?? "off"
        ipListText = loaded.ipList.joined(separator: "\n")
    }

    private func apply() async {
        let list = ipListText
            .split(whereSeparator: { $0.isWhitespace || $0 == "," })
            .map(String.init)
            .filter { !$0.isEmpty }

        await runner.run("security", success: "Security applied.") {
            let updated = try await OrchestratorAPI.shared.updateSecurity(
                siteID: site.id,
                basicAuth: basicAuth,
                basicUser: basicUser,
                basicPassword: basicPassword,
                ipMode: ipMode,
                ipList: list
            )
            security = updated
            basicPassword = ""
        }
    }
}
