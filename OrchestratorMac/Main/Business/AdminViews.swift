import OrchestratorKit
import SwiftUI

/// Users and their roles, and API tokens (revoke needs Touch ID). Adding users and tokens
/// stays in the web panel, where the one-time secrets are shown.
struct UsersAccessView: View {
    let environment: AppEnvironment

    @State private var users: [User] = []
    @State private var tokens: [APIToken] = []
    @State private var loaded = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let error { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Color.statusDangerText) }
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Users", trailing: "Add in Web Panel") { WebPanel.open(.home) }
                    if users.isEmpty {
                        EmptyRow(text: loaded ? "No users, or your account can’t list them" : "Loading…", symbol: "person.2")
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(users.enumerated()), id: \.element.id) { index, user in
                                if index > 0 { Divider() }
                                HStack(spacing: 10) {
                                    Text(user.initials)
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 26, height: 26)
                                        .background(Circle().fill(Color.accentColor))
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(user.email).font(.system(size: 13))
                                        Text(siteAccess(user))
                                            .font(.system(size: 11)).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Tag(text: (user.role ?? "user").capitalized)
                                    Text(user.totpEnabled == true ? "2FA on" : "2FA off")
                                        .font(.system(size: 11))
                                        .foregroundStyle(user.totpEnabled == true ? Color.statusSuccessText : Color.statusWarningText)
                                        .frame(width: 56, alignment: .trailing)
                                }
                                .padding(.horizontal, 12)
                                .frame(height: 44)
                                .accessibilityElement(children: .combine)
                            }
                        }
                        .card()
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "API tokens", trailing: "Create in Web Panel") { WebPanel.open(.tokens) }
                    if tokens.isEmpty {
                        EmptyRow(text: loaded ? "No tokens" : "Loading…", symbol: "key")
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(tokens.enumerated()), id: \.element.id) { index, token in
                                if index > 0 { Divider() }
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(token.name).font(.system(size: 13, weight: .medium))
                                        Text(token.tokenPrefix.map { "\($0)…" } ?? "").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(token.lastUsedAt.map { "Used \(RelativeTime.ago($0))" } ?? "Never used")
                                        .font(.system(size: 11)).foregroundStyle(.secondary)
                                    Text(token.expiresAt.map { "Expires \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "No expiry")
                                        .font(.system(size: 11)).foregroundStyle(.secondary)
                                        .frame(width: 130, alignment: .trailing)
                                    Button("Revoke…") {
                                        Task { if await environment.executor.revokeToken(token) { await load() } }
                                    }
                                    .buttonStyle(RowButtonStyle())
                                    .help("Asks for confirmation and Touch ID")
                                }
                                .padding(.horizontal, 12)
                                .frame(height: 44)
                            }
                        }
                        .card()
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .task { await load() }
    }

    /// Admins see every site; other roles see all sites or the ones assigned to them.
    private func siteAccess(_ user: User) -> String {
        if (user.role ?? "").lowercased() == "admin" || user.allSitesAccess == true { return "All sites" }
        return "Assigned sites only"
    }

    private func load() async {
        async let people = try? environment.api.users()
        async let keys = try? environment.api.tokens()
        users = await people ?? []
        tokens = await keys ?? []
        error = users.isEmpty && tokens.isEmpty ? "Could not load users or tokens." : nil
        loaded = true
    }
}

/// Everything done in the panel, newest first, 50 at a time.
struct AuditLogView: View {
    let environment: AppEnvironment
    let model: MainWindowModel

    @State private var entries: [AuditEntry] = []
    @State private var total: Int?
    @State private var isLoading = false
    @State private var filter = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Filter by action, user or detail", text: $filter)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
                Spacer()
                Text(total.map { "\(entries.count) of \($0)" } ?? "\(entries.count)").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .controlSize(.small)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            Divider()
            List {
                ForEach(shown) { entry in
                    HStack(spacing: 12) {
                        Image(systemName: entry.symbol).foregroundStyle(entry.tone.color).frame(width: 18).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.action).font(.system(size: 12, weight: .medium, design: .monospaced))
                            if let summary = entry.metaSummary {
                                Text(summary).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                        Spacer()
                        if let siteID = entry.siteId, let site = environment.store.site(id: siteID) {
                            Button(site.domain) { model.openSite(siteID) }.buttonStyle(.link).font(.system(size: 11))
                        }
                        Text(entry.userEmail ?? "System").font(.system(size: 11)).foregroundStyle(.secondary)
                            .frame(width: 160, alignment: .trailing).lineLimit(1)
                        Text(entry.createdAt?.formatted(date: .abbreviated, time: .shortened) ?? "")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(width: 170, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
                if (total ?? 0) > entries.count {
                    Button(isLoading ? "Loading…" : "Load More") { Task { await load(reset: false) } }
                        .disabled(isLoading)
                        .frame(maxWidth: .infinity)
                }
            }
            .listStyle(.inset)
        }
        .task { await load(reset: true) }
    }

    private var shown: [AuditEntry] {
        let needle = filter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return entries }
        return entries.filter {
            [$0.action, $0.userEmail ?? "", $0.metaSummary ?? ""].contains { $0.lowercased().contains(needle) }
        }
    }

    private func load(reset: Bool) async {
        isLoading = true
        defer { isLoading = false }
        guard let page = try? await environment.api.audit(limit: 50, offset: reset ? 0 : entries.count) else { return }
        entries = reset ? page.logs : entries + page.logs
        total = page.total
    }
}

/// Automation rules and outbound webhooks, read-only; editing stays in the web panel.
struct AutomationView: View {
    let environment: AppEnvironment

    @State private var rules: [AutomationRule] = []
    @State private var hooks: [OutboundWebhook] = []
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Rules", trailing: "Edit in Web Panel") { WebPanel.open(.home) }
                    if rules.isEmpty {
                        EmptyRow(text: loaded ? "No automation rules" : "Loading…", symbol: "bolt")
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(rules.enumerated()), id: \.element.id) { index, rule in
                                if index > 0 { Divider() }
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(rule.name).font(.system(size: 13))
                                        Text("When \(rule.trigger) → \(rule.actionType)")
                                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if rule.dryRun { Tag(text: "Dry run", tint: .statusWarningText) }
                                    Text(rule.lastFiredAt.map { "Fired \(RelativeTime.ago($0))" } ?? "Never fired")
                                        .font(.system(size: 11)).foregroundStyle(.secondary)
                                    Text(rule.enabled ? "On" : "Off")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(rule.enabled ? Color.statusSuccessText : .secondary)
                                        .frame(width: 30, alignment: .trailing)
                                }
                                .padding(.horizontal, 12)
                                .frame(height: 44)
                                .accessibilityElement(children: .combine)
                            }
                        }
                        .card()
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Webhooks")
                    if hooks.isEmpty {
                        EmptyRow(text: loaded ? "No webhooks" : "Loading…", symbol: "link")
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(hooks.enumerated()), id: \.element.id) { index, hook in
                                if index > 0 { Divider() }
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(hook.name).font(.system(size: 13))
                                        Text(URL(string: hook.url)?.host() ?? hook.url).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(hook.events.isEmpty ? "All events" : "\(hook.events.count) events")
                                        .font(.system(size: 11)).foregroundStyle(.secondary)
                                    Text(hook.active ? "Active" : "Paused")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(hook.active ? Color.statusSuccessText : .secondary)
                                        .frame(width: 50, alignment: .trailing)
                                }
                                .padding(.horizontal, 12)
                                .frame(height: 44)
                                .accessibilityElement(children: .combine)
                            }
                        }
                        .card()
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .task {
            async let ruleList = try? environment.api.automationRules()
            async let hookList = try? environment.api.webhooks()
            rules = await ruleList ?? []
            hooks = await hookList ?? []
            loaded = true
        }
    }
}
