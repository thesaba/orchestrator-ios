import SwiftUI

struct OverviewView: View {
    @State private var model = OverviewViewModel()
    @State private var showsSettings = false

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            Group {
                if let error = model.fatalError, !model.hasLoadedOnce || model.sites.isEmpty {
                    ErrorStateView(error: error) { Task { await model.load() } }
                } else if model.sites.isEmpty && model.isLoading {
                    LoadingStateView(title: "Loading your panel…")
                } else {
                    content
                }
            }
            .navigationTitle("Overview")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await model.load() }
            .task { if !model.hasLoadedOnce { await model.load() } }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    OrchestratorWordmark(size: 22)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showsSettings) {
                SettingsView()
            }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 14) {
                if !model.degradedSections.isEmpty {
                    InlineErrorBanner(
                        message: "Could not load: \(model.degradedSections.joined(separator: ", ")). Pull to retry."
                    )
                }

                fleetTiles
                serverCard
                if !model.sitesDown.isEmpty { downCard }
                if !model.expiringCertificates.isEmpty { certificatesCard }
                if !model.attentionSites.isEmpty { attentionCard }
                deploymentsCard
                if let billing = model.billing { billingCard(billing) }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Cards

    private var fleetTiles: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            MetricTile(
                title: "Sites",
                value: "\(model.sites.count)",
                caption: "\(model.activeSites) healthy",
                tone: model.attentionSites.isEmpty ? .good : .warning,
                systemImage: "globe"
            )
            MetricTile(
                title: "Uptime monitors",
                value: "\(model.uptimeMonitored - model.sitesDown.count)/\(model.uptimeMonitored)",
                caption: model.sitesDown.isEmpty ? "all responding" : "\(model.sitesDown.count) down",
                tone: model.sitesDown.isEmpty ? .good : .critical,
                systemImage: "waveform.path.ecg"
            )
            MetricTile(
                title: "Unread",
                value: "\(model.unreadNotifications)",
                caption: "notifications",
                tone: model.unreadNotifications > 0 ? .info : .neutral,
                systemImage: "bell"
            )
            MetricTile(
                title: "Open errors",
                value: "\(model.openErrors)",
                caption: "unresolved",
                tone: model.openErrors > 0 ? .warning : .good,
                systemImage: "exclamationmark.triangle"
            )
        }
    }

    private var serverCard: some View {
        SectionCard("Server", systemImage: "server.rack") {
            if let system = model.system {
                VStack(alignment: .leading, spacing: 14) {
                    UsageBar(
                        label: "CPU",
                        percent: system.cpu.percent,
                        detail: system.cpu.cores.map { "\($0) cores · load \(String(format: "%.2f", system.cpu.load1 ?? 0))" }
                    )
                    UsageBar(
                        label: "Memory",
                        percent: system.ram.percent,
                        detail: "\(Bytes.string(system.ram.used)) of \(Bytes.string(system.ram.total))"
                    )
                    UsageBar(
                        label: "Disk",
                        percent: system.disk.percent,
                        detail: "\(Bytes.string(system.disk.used)) of \(Bytes.string(system.disk.total))"
                    )
                    Divider()
                    DetailRow(label: "Host", value: system.hostname, monospaced: true)
                    DetailRow(label: "Uptime", value: Durations.uptime(system.uptime))
                }
            } else {
                Text("Unavailable")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var downCard: some View {
        SectionCard("Not responding", systemImage: "bolt.horizontal.circle") {
            VStack(spacing: 10) {
                ForEach(model.sitesDown) { entry in
                    HStack {
                        StatusDot(tone: .critical)
                        Text(entry.domain)
                            .font(.callout.weight(.medium))
                        Spacer()
                        if let code = entry.statusCode {
                            Text("HTTP \(code)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Text(entry.checkedAt.relativeShortOrDash)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var certificatesCard: some View {
        SectionCard("Certificates expiring", systemImage: "lock.shield") {
            VStack(spacing: 10) {
                ForEach(model.expiringCertificates) { entry in
                    HStack {
                        StatusDot(tone: entry.tone)
                        Text(entry.domain)
                            .font(.callout)
                        Spacer()
                        if let error = entry.error {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .lineLimit(1)
                        } else {
                            Text((entry.daysLeft ?? 0).daysLabel)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(entry.tone.color)
                        }
                    }
                }
            }
        }
    }

    private var attentionCard: some View {
        SectionCard("Needs attention", systemImage: "exclamationmark.circle") {
            VStack(spacing: 10) {
                ForEach(model.attentionSites) { site in
                    NavigationLink {
                        SiteDetailView(siteID: site.id, initialSite: site)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(site.name).font(.callout.weight(.medium))
                                Text(site.domain).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            StatusBadge(status: site.statusLabel, tone: site.tone)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var deploymentsCard: some View {
        SectionCard("Latest deploys", systemImage: "arrow.up.circle") {
            if model.recentDeployments.isEmpty {
                Text("No deploys recorded yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(model.recentDeployments) { item in
                        HStack(alignment: .top) {
                            StatusDot(tone: item.deployment.tone)
                                .padding(.top, 5)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.site.domain)
                                    .font(.callout.weight(.medium))
                                Text("\(item.deployment.branch ?? "—") @ \(item.deployment.shortCommit)")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(item.deployment.createdAt.relativeShortOrDash)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func billingCard(_ billing: BillingOverview) -> some View {
        SectionCard(
            "Billing",
            systemImage: "creditcard",
            accessory: AnyView(StatusBadge(status: billing.mode, tone: billing.enforcementTone))
        ) {
            LazyVGrid(columns: columns, spacing: 12) {
                MetricTile(
                    title: "MRR",
                    value: Money.string(billing.mrr, currency: billing.currencyCode),
                    caption: "\(billing.subscriptions ?? 0) subscriptions"
                )
                MetricTile(
                    title: "Outstanding",
                    value: Money.string(billing.outstanding, currency: billing.currencyCode),
                    caption: "\(billing.clients ?? 0) clients",
                    tone: (billing.outstanding ?? 0) > 0 ? .warning : .good
                )
                MetricTile(
                    title: "Suspended",
                    value: "\(billing.suspended ?? 0)",
                    caption: "sites",
                    tone: (billing.suspended ?? 0) > 0 ? .critical : .good
                )
                MetricTile(
                    title: "Past due",
                    value: "\(billing.pastDue ?? 0)",
                    caption: "sites",
                    tone: (billing.pastDue ?? 0) > 0 ? .warning : .good
                )
            }
        }
    }
}
