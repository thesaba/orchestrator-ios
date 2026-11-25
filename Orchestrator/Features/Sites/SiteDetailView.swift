import SwiftUI
import Charts
import OrchestratorKit

struct SiteDetailView: View {
    @State private var model: SiteDetailViewModel

    init(siteID: Int, initialSite: Site? = nil) {
        _model = State(initialValue: SiteDetailViewModel(siteID: siteID, initialSite: initialSite))
    }

    var body: some View {
        Group {
            if let site = model.site {
                content(site)
            } else if let error = model.loadError {
                ErrorStateView(error: error) { Task { await model.load() } }
            } else {
                LoadingStateView()
            }
        }
        .navigationTitle(model.site?.name ?? "Site")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.load() }
        .task { await model.load() }
    }

    private func content(_ site: Site) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                if !model.degradedSections.isEmpty {
                    InlineErrorBanner(message: "Could not load: \(model.degradedSections.joined(separator: ", ")).")
                }

                headerCard(site)
                SiteActionsCard(site: site) { await model.load() }
                if let health = model.health { healthCard(health) }
                responseCard
                certificateCard(site)
                deploymentsCard
                repositoryCard(site)
                configurationCard(site)
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Cards

    private func headerCard(_ site: Site) -> some View {
        SectionCard(site.domain, systemImage: "globe", accessory: AnyView(StatusBadge(status: site.statusLabel, tone: site.tone))) {
            VStack(alignment: .leading, spacing: 10) {
                if site.billingSuspended {
                    InlineErrorBanner(message: "This site is suspended by billing enforcement.")
                } else if site.billingPastDue {
                    Label("Invoice past due", systemImage: "creditcard.trianglebadge.exclamationmark")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                if site.maintenanceMode {
                    Label("Maintenance mode is on", systemImage: "wrench.and.screwdriver")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }

                DetailRow(label: "PHP", value: site.phpVersion)
                DetailRow(label: "Branch", value: site.branch, monospaced: true)
                DetailRow(label: "Root", value: site.rootPath, monospaced: true)
                if !site.tagList.isEmpty {
                    DetailRow(label: "Tags", value: site.tagList.joined(separator: ", "))
                }
                if let url = site.displayURL {
                    Link(destination: url) {
                        Label("Open \(site.domain)", systemImage: "safari")
                            .font(.footnote)
                    }
                }
            }
        }
    }

    private func healthCard(_ health: HealthScore) -> some View {
        SectionCard("Health score", systemImage: "heart.text.square") {
            HStack(alignment: .center, spacing: 20) {
                ZStack {
                    Circle()
                        .stroke(Color(.tertiarySystemFill), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: CGFloat(max(0, min(100, health.score))) / 100)
                        .stroke(health.tone.color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(health.score)")
                        .font(.title3.weight(.bold).monospacedDigit())
                }
                .frame(width: 74, height: 74)

                VStack(alignment: .leading, spacing: 6) {
                    if let breakdown = health.breakdown {
                        breakdownRow("Uptime", breakdown.uptime, of: 40)
                        breakdownRow("Deploys", breakdown.deploy, of: 30)
                        breakdownRow("SSL", breakdown.ssl, of: 20)
                        breakdownRow("Maintenance", breakdown.maintenance, of: 10)
                    }
                    if let level = health.enforcementLevel, level != "none" {
                        Text("Enforcement: \(level)")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
            }
        }
    }

    private func breakdownRow(_ label: String, _ value: Int?, of maximum: Int) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(value ?? 0)/\(maximum)")
                .font(.caption.monospacedDigit())
                .foregroundStyle((value ?? 0) >= maximum ? Color.green : Color.orange)
        }
    }

    private var responseCard: some View {
        SectionCard("Response time", systemImage: "speedometer") {
            if model.sparkline.isEmpty {
                Text("No samples in the last hours.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Chart(model.sparkline) { point in
                        AreaMark(
                            x: .value("Time", point.at),
                            y: .value("ms", point.ms ?? 0)
                        )
                        .foregroundStyle(.linearGradient(
                            colors: [.accentColor.opacity(0.35), .accentColor.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                        LineMark(
                            x: .value("Time", point.at),
                            y: .value("ms", point.ms ?? 0)
                        )
                        .foregroundStyle(Color.accentColor)
                        .interpolationMethod(.monotone)
                    }
                    .chartYAxisLabel("ms")
                    .frame(height: 130)

                    HStack(spacing: 18) {
                        if let average = model.averageResponse {
                            Label(Durations.milliseconds(average), systemImage: "chart.bar")
                        }
                        if let uptime = model.uptime24h {
                            Label("\(uptime)% / 24h", systemImage: "checkmark.seal")
                                .foregroundStyle(uptime >= 99 ? Color.green : Color.orange)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func certificateCard(_ site: Site) -> some View {
        SectionCard("Certificate", systemImage: "lock.shield") {
            if let ssl = model.ssl {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        StatusBadge(
                            ssl.active ? "active" : "inactive",
                            tone: ssl.active ? site.sslTone : .neutral
                        )
                        Spacer()
                        if ssl.running {
                            Label("Issuing…", systemImage: "clock")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                    }
                    DetailRow(label: "Expires", value: ssl.expiresAt.shortDateTimeOrDash)
                    DetailRow(label: "Days left", value: ssl.daysLeft.map { $0.daysLabel })
                    DetailRow(label: "Issuer", value: ssl.issuer)
                }
            } else {
                Text(site.sslEnabled ? "Unavailable" : "SSL is not enabled for this site.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var deploymentsCard: some View {
        SectionCard("Deployments", systemImage: "arrow.up.circle") {
            if model.deployments.isEmpty {
                Text("No deploys recorded.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 12) {
                    ForEach(model.deployments) { deployment in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                StatusBadge(status: deployment.status, tone: deployment.tone)
                                Spacer()
                                Text(deployment.createdAt.relativeShortOrDash)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text("\(deployment.branch ?? "—") @ \(deployment.shortCommit)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                            if let tests = deployment.testSummary {
                                Label(tests, systemImage: "checkmark.diamond")
                                    .font(.caption2)
                                    .foregroundStyle(deployment.testTone.color)
                            }
                        }
                        if deployment.id != model.deployments.last?.id { Divider() }
                    }
                }
            }
        }
    }

    private func repositoryCard(_ site: Site) -> some View {
        SectionCard("Repository", systemImage: "shippingbox") {
            VStack(alignment: .leading, spacing: 8) {
                DetailRow(label: "Repo", value: site.repoUrl, monospaced: true)
                DetailRow(label: "Branch", value: site.branch, monospaced: true)
                DetailRow(label: "Git token", value: site.hasGitToken ? "configured" : "none")
                DetailRow(label: "Queued deploy", value: site.deployQueued ? "yes" : "no")
            }
        }
    }

    private func configurationCard(_ site: Site) -> some View {
        SectionCard("Configuration", systemImage: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 8) {
                DetailRow(label: "Database", value: site.dbName, monospaced: true)
                DetailRow(label: "DB user", value: site.dbUser, monospaced: true)
                DetailRow(label: "Health check", value: site.healthCheck ? (site.healthCheckUrl ?? "enabled") : "off")
                DetailRow(label: "Tests", value: site.runTests ? (site.testCommand ?? "enabled") : "off", monospaced: site.runTests)
                DetailRow(label: "On test failure", value: site.testFailureMode)
                DetailRow(label: "Uptime monitor", value: site.uptimeMonitor ? "on" : "off")
                DetailRow(label: "Status page", value: site.statusPageEnabled ? "public" : "off")
                DetailRow(label: "Basic auth", value: site.secBasicAuth ? (site.secBasicUser ?? "on") : "off")
                DetailRow(label: "Created", value: site.createdAt.shortDateTimeOrDash)
            }
        }
    }
}
