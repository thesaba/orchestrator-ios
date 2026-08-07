import SwiftUI

// MARK: - Alert rules

struct AlertRulesView: View {
    @State private var state: LoadState<[AlertRule]> = .idle
    @State private var runner = ActionRunner()
    @State private var showsComposer = false

    var body: some View {
        LoadStateView(
            state: state,
            emptyTitle: "No alert rules",
            emptyMessage: "Add a rule to be told when a metric crosses a threshold.",
            emptyIcon: "bell.badge",
            isEmpty: { $0.isEmpty },
            retry: { Task { await load() } }
        ) { rules in
            List {
                Section {
                    ActionFeedbackView(runner: runner)
                        .listRowBackground(Color.clear)
                }
                ForEach(rules) { rule in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(rule.summary)
                                .font(.callout.monospaced())
                            Spacer()
                            StatusBadge(rule.enabled ? "on" : "off",
                                        tone: rule.enabled ? .good : .neutral, showsSymbol: false)
                        }
                        HStack(spacing: 12) {
                            if let cooldown = rule.cooldownMins {
                                Text("cooldown \(cooldown)m")
                            }
                            if let last = rule.lastTriggeredAt {
                                Text("last fired \(last.relativeShort)")
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                    .swipeActions {
                        Button(role: .destructive) {
                            Task { await delete(rule) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            Task { await toggle(rule) }
                        } label: {
                            Label(rule.enabled ? "Disable" : "Enable",
                                  systemImage: rule.enabled ? "bell.slash" : "bell")
                        }
                        .tint(.blue)
                    }
                }
            }
        }
        .navigationTitle("Alert rules")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { if state.value == nil { await load() } }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showsComposer = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showsComposer) {
            AlertRuleComposerView { draft in
                await runner.run("create", success: "Rule created.") {
                    try await OrchestratorAPI.shared.createAlertRule(draft)
                } onSuccess: { await load() }
            }
        }
    }

    private func load() async {
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await OrchestratorAPI.shared.alertRules())
        } catch {
            state = .failed(APIError.wrap(error))
        }
    }

    private func toggle(_ rule: AlertRule) async {
        await runner.run("toggle-\(rule.id)") {
            try await OrchestratorAPI.shared.updateAlertRule(
                id: rule.id,
                AlertRuleDraft(metric: rule.metric, operator: rule.comparison,
                               threshold: rule.threshold, enabled: !rule.enabled,
                               cooldownMins: rule.cooldownMins)
            )
        } onSuccess: { await load() }
    }

    private func delete(_ rule: AlertRule) async {
        await runner.run("delete-\(rule.id)", success: "Rule deleted.") {
            try await OrchestratorAPI.shared.deleteAlertRule(id: rule.id)
        } onSuccess: { await load() }
    }
}

struct AlertRuleComposerView: View {
    var onCreate: (AlertRuleDraft) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var metric = "cpu"
    @State private var comparison = ">"
    @State private var threshold = 90
    @State private var cooldown = 30

    private let metrics = ["cpu", "ram", "disk", "swap", "load"]

    var body: some View {
        NavigationStack {
            Form {
                Picker("Metric", selection: $metric) {
                    ForEach(metrics, id: \.self) { Text($0.uppercased()).tag($0) }
                }
                Picker("Operator", selection: $comparison) {
                    Text("greater than").tag(">")
                    Text("less than").tag("<")
                }
                Stepper("Threshold: \(threshold)%", value: $threshold, in: 1...100, step: 5)
                Stepper("Cooldown: \(cooldown) min", value: $cooldown, in: 5...240, step: 5)
            }
            .navigationTitle("New rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            await onCreate(AlertRuleDraft(metric: metric, operator: comparison,
                                                          threshold: threshold, enabled: true,
                                                          cooldownMins: cooldown))
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Audit log

struct AuditLogView: View {
    @State private var entries: [AuditEntry] = []
    @State private var total = 0
    @State private var loadError: APIError?
    @State private var isLoadingMore = false
    @State private var hasLoaded = false

    private let pageSize = 50

    var body: some View {
        List {
            if let loadError {
                Section { InlineErrorBanner(message: loadError.errorDescription ?? "Failed") }
            }

            ForEach(entries) { entry in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: entry.symbol)
                        .foregroundStyle(entry.tone == .neutral ? Color.secondary : entry.tone.color)
                        .frame(width: 22)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(entry.action)
                                .font(.callout.monospaced())
                            Spacer()
                            Text(entry.createdAt.relativeShortOrDash)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(entry.userEmail ?? "system")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let meta = entry.metaSummary {
                            Text(meta)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(2)
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            if entries.count < total {
                Button {
                    Task { await loadMore() }
                } label: {
                    HStack {
                        Spacer()
                        if isLoadingMore { ProgressView() } else { Text("Load more (\(total - entries.count) left)") }
                        Spacer()
                    }
                }
                .disabled(isLoadingMore)
            }
        }
        .navigationTitle("Audit log")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }
        .task { if !hasLoaded { await reload() } }
    }

    private func reload() async {
        hasLoaded = true
        do {
            let response = try await OrchestratorAPI.shared.audit(limit: pageSize, offset: 0)
            entries = response.logs
            total = response.total ?? response.logs.count
            loadError = nil
        } catch {
            loadError = APIError.wrap(error)
        }
    }

    private func loadMore() async {
        isLoadingMore = true
        defer { isLoadingMore = false }
        guard let response = try? await OrchestratorAPI.shared.audit(limit: pageSize, offset: entries.count) else { return }
        entries.append(contentsOf: response.logs)
        total = response.total ?? total
    }
}

// MARK: - Users

struct UsersView: View {
    @State private var state: LoadState<[User]> = .idle
    @State private var runner = ActionRunner()
    @State private var showsComposer = false
    @State private var pendingDelete: User?

    var body: some View {
        LoadStateView(
            state: state,
            emptyTitle: "No users",
            emptyMessage: nil,
            emptyIcon: "person.2",
            isEmpty: { $0.isEmpty },
            retry: { Task { await load() } }
        ) { users in
            List {
                Section {
                    ActionFeedbackView(runner: runner)
                        .listRowBackground(Color.clear)
                }
                ForEach(users) { user in
                    NavigationLink {
                        UserSitesView(user: user)
                    } label: {
                        HStack {
                            Text(user.initials)
                                .font(.caption.weight(.semibold))
                                .frame(width: 32, height: 32)
                                .background(Color.accentColor.opacity(0.15), in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.email)
                                    .font(.callout)
                                Text(user.role?.capitalized ?? "—")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if user.allSitesAccess == true {
                                StatusBadge("all sites", tone: .info, showsSymbol: false)
                            }
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) { pendingDelete = user } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle("Users")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { if state.value == nil { await load() } }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showsComposer = true } label: { Image(systemName: "person.badge.plus") }
            }
        }
        .sheet(isPresented: $showsComposer) {
            UserComposerView { draft in
                await runner.run("create", success: "User created.") {
                    try await OrchestratorAPI.shared.createUser(draft)
                } onSuccess: { await load() }
            }
        }
        .confirmationDialog(
            "Delete \(pendingDelete?.email ?? "")?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let user = pendingDelete else { return }
                pendingDelete = nil
                Task { await delete(user) }
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("The account is removed and its API tokens stop working immediately.")
        }
    }

    private func load() async {
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await OrchestratorAPI.shared.users())
        } catch {
            state = .failed(APIError.wrap(error))
        }
    }

    private func delete(_ user: User) async {
        await runner.run("delete-\(user.id)", success: "User deleted.") {
            try await OrchestratorAPI.shared.deleteUser(id: user.id)
        } onSuccess: { await load() }
    }
}

struct UserComposerView: View {
    var onCreate: (UserDraft) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var role = "developer"
    @State private var allSites = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Email", text: $email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
                Picker("Role", selection: $role) {
                    Text("Admin").tag("admin")
                    Text("Developer").tag("developer")
                    Text("Viewer").tag("viewer")
                }
                Toggle("Access to all sites", isOn: $allSites)
            }
            .navigationTitle("New user")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            await onCreate(UserDraft(email: email.trimmingCharacters(in: .whitespaces),
                                                     password: password, role: role,
                                                     allSitesAccess: allSites))
                            dismiss()
                        }
                    }
                    .disabled(email.isEmpty || password.count < 8)
                }
            }
        }
    }
}

struct UserSitesView: View {
    let user: User

    @State private var sites: [Site] = []
    @State private var selected: Set<Int> = []
    @State private var runner = ActionRunner()
    @State private var hasLoaded = false

    var body: some View {
        List {
            Section {
                ActionFeedbackView(runner: runner)
                    .listRowBackground(Color.clear)
            } footer: {
                Text(user.allSitesAccess == true
                     ? "This account has blanket access to every site, so the per-site list below is not consulted."
                     : "Only the selected sites are visible to this account.")
            }

            Section("Sites") {
                ForEach(sites) { site in
                    Button {
                        if selected.contains(site.id) { selected.remove(site.id) } else { selected.insert(site.id) }
                    } label: {
                        HStack {
                            Image(systemName: selected.contains(site.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selected.contains(site.id) ? Color.accentColor : Color.secondary)
                            Text(site.domain)
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Section {
                Button("Save access") { Task { await save() } }
                    .disabled(runner.isRunning || !hasLoaded)
            }
        }
        .navigationTitle(user.email)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            sites = (try? await OrchestratorAPI.shared.sites()) ?? []
            selected = Set((try? await OrchestratorAPI.shared.userSites(id: user.id)) ?? [])
            hasLoaded = true
        }
    }

    private func save() async {
        await runner.run("save", success: "Access updated.") {
            try await OrchestratorAPI.shared.setUserSites(id: user.id, siteIDs: Array(selected).sorted())
        }
    }
}

// MARK: - Telegram & digest

struct TelegramView: View {
    @State private var status: TelegramStatus?
    @State private var linkCode: TelegramLinkCode?
    @State private var runner = ActionRunner()

    var body: some View {
        List {
            Section {
                ActionFeedbackView(runner: runner)
                    .listRowBackground(Color.clear)
            }

            Section("Status") {
                if let status {
                    HStack {
                        Text("Account")
                        Spacer()
                        StatusBadge(status.linked ? "linked" : "not linked",
                                    tone: status.linked ? .good : .neutral)
                    }
                    if status.linked {
                        DetailRow(label: "Username", value: status.username.map { "@\($0)" })
                        DetailRow(label: "Linked", value: status.linkedAt.shortDateTimeOrDash)
                    }
                    DetailRow(label: "Bot", value: status.botUsername.map { "@\($0)" } ?? (status.botConfigured ? "configured" : "not configured"))
                    HStack {
                        Text("Webhook")
                        Spacer()
                        StatusBadge(status.webhookConfigured ? "active" : "off",
                                    tone: status.webhookConfigured ? .good : .warning)
                    }
                } else {
                    ProgressView()
                }
            }

            if let code = linkCode {
                Section("Link code") {
                    Text(code.code ?? "—")
                        .font(.title2.monospaced().weight(.semibold))
                        .textSelection(.enabled)
                    if let url = code.url, let link = URL(string: url) {
                        Link("Open in Telegram", destination: link)
                    }
                    Text("Send this code to the bot to finish linking.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                if status?.linked == true {
                    Button("Unlink account", role: .destructive) { Task { await unlink() } }
                } else {
                    Button("Get link code") { Task { await requestCode() } }
                }
                Button(status?.webhookConfigured == true ? "Re-register webhook" : "Register webhook") {
                    Task { await setupWebhook() }
                }
                if status?.webhookConfigured == true {
                    Button("Remove webhook", role: .destructive) { Task { await removeWebhook() } }
                }
            }
            .disabled(runner.isRunning)
        }
        .navigationTitle("Telegram")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        status = try? await OrchestratorAPI.shared.telegramStatus()
    }

    private func requestCode() async {
        await runner.run("code") {
            linkCode = try await OrchestratorAPI.shared.telegramLinkCode()
        }
    }

    private func unlink() async {
        await runner.run("unlink", success: "Account unlinked.") {
            try await OrchestratorAPI.shared.unlinkTelegram()
        } onSuccess: { await load() }
    }

    private func setupWebhook() async {
        await runner.run("setup", success: "Webhook registered.") {
            try await OrchestratorAPI.shared.setupTelegramWebhook()
        } onSuccess: { await load() }
    }

    private func removeWebhook() async {
        await runner.run("remove", success: "Webhook removed.") {
            try await OrchestratorAPI.shared.removeTelegramWebhook()
        } onSuccess: { await load() }
    }
}

struct DigestView: View {
    @State private var digest: DigestSettings?
    @State private var runner = ActionRunner()
    @State private var day = 1

    private let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    var body: some View {
        List {
            Section {
                ActionFeedbackView(runner: runner)
                    .listRowBackground(Color.clear)
            }

            Section {
                if let digest {
                    Toggle("Weekly digest", isOn: Binding(
                        get: { digest.enabled },
                        set: { value in Task { await update(enabled: value, day: day) } }
                    ))
                    Picker("Send on", selection: Binding(
                        get: { day },
                        set: { value in day = value; Task { await update(enabled: digest.enabled, day: value) } }
                    )) {
                        ForEach(Array(weekdays.enumerated()), id: \.offset) { index, name in
                            Text(name).tag(index)
                        }
                    }
                    if let lastSent = digest.lastSent {
                        DetailRow(label: "Last sent", value: lastSent)
                    }
                } else {
                    ProgressView()
                }
            }
            .disabled(runner.isRunning)

            if let preview = digest?.preview {
                Section("This week so far") {
                    DetailRow(label: "Deploys", value: "\(preview.deploySuccess ?? 0) ok · \(preview.deployFailed ?? 0) failed")
                    DetailRow(label: "Uptime", value: preview.uptimePct.map { "\($0)%" })
                    DetailRow(label: "Avg response", value: Durations.milliseconds(preview.avgMs))
                    DetailRow(label: "Errors", value: "\(preview.errOpen ?? 0) open · \(preview.errNew ?? 0) new")
                    DetailRow(label: "Sites", value: preview.sites.map(String.init))
                    DetailRow(label: "Since", value: preview.since.shortDateTimeOrDash)
                }
            }

            Section {
                Button("Send digest now") { Task { await sendNow() } }
                    .disabled(runner.isRunning)
            } footer: {
                Text("Delivers the summary immediately to the configured channels.")
            }
        }
        .navigationTitle("Weekly digest")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        digest = try? await OrchestratorAPI.shared.digest()
        day = digest?.day ?? 1
    }

    private func update(enabled: Bool, day: Int) async {
        await runner.run("digest", success: "Saved.") {
            try await OrchestratorAPI.shared.updateDigest(DigestPatch(enabled: enabled, day: day))
        } onSuccess: { await load() }
    }

    private func sendNow() async {
        await runner.run("send", success: "Digest sent.") {
            try await OrchestratorAPI.shared.sendDigestNow()
        }
    }
}
