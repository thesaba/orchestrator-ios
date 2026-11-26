import OrchestratorKit
import SwiftUI

/// The selected site: state, the main actions, facts and its response time.
///
/// Every action that changes production goes through `CommandExecutor`, which confirms
/// first and asks for Touch ID where the action requires it.
struct SiteInspector: View {
    let environment: AppEnvironment
    let model: MainWindowModel
    var row: SiteTableRow
    @State private var responseExpanded = false

    private var executor: CommandExecutor { environment.executor }
    private var listing: SiteListing? { environment.store.siteListings?.first { $0.id == row.id } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                Button {
                    model.openSite(row.id)
                } label: {
                    Label("Open Site Page", systemImage: "arrow.up.right.square").frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                if row.isDeploying { deployingCard }
                actions
                facts
                response
                more
            }
            .padding(16)
        }
        .sheet(isPresented: $responseExpanded) {
            SiteResponseSheet(data: model.data, siteID: row.id, domain: row.domain)
        }
        .onAppear { model.data.requestSparklines(for: [row.id]) }
        .onChange(of: row.id) { _, id in model.data.requestSparklines(for: [id]) }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(String(row.domain.prefix(1)).uppercased())
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.accentText)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.tintInfo))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.domain)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .textSelection(.enabled)
                HStack(spacing: 6) {
                    StatusMarkView(mark: row.mark, size: 11)
                    Text(row.label)
                        .font(.system(size: 11))
                        .foregroundStyle(row.mark.textTint)
                    if row.name.caseInsensitiveCompare(row.domain) != .orderedSame {
                        Text("· \(row.name)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
            }
        }
    }

    private var deployingCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(deployHeadline)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentText)
            if let message = row.deploy?.commitMessage {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if let progress = row.deploy?.progress {
                ProgressBar(fraction: progress, tint: .brandTeal)
            } else {
                ProgressView().progressViewStyle(.linear).controlSize(.mini)
            }
            Button("Show live log") {
                if let site = environment.store.site(id: row.id) { environment.logs.showLiveDeploy(for: site) }
            }
            .buttonStyle(.link)
            .font(.system(size: 12, weight: .medium))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: .tintInfo)
    }

    private var deployHeadline: String {
        guard let step = row.deploy?.currentStep else { return "Deploying" }
        return "Deploying · step \(step.number) of \(row.deploy?.totalSteps ?? step.total) · \(step.title)"
    }

    private var actions: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                Button {
                    let id = row.id
                    Task { await executor.deploy(siteID: id, ref: nil) }
                } label: {
                    Text(row.isDeploying ? "Deploying…" : "Deploy…").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(row.isDeploying)
                .help("Deploy \(row.domain) (asks for confirmation)")
                Button {
                    if let url = URL(string: "https://\(row.domain)") { NSWorkspace.shared.open(url) }
                } label: {
                    Text("Open Site").frame(maxWidth: .infinity)
                }
            }
            GridRow {
                Button {
                    environment.open(.deployLog(siteID: row.id))
                } label: {
                    Text("Deploy Log").frame(maxWidth: .infinity)
                }
                Button {
                    let id = row.id
                    Task { await executor.rollback(siteID: id) }
                } label: {
                    Text("Roll Back…").frame(maxWidth: .infinity)
                }
                .help("Asks for confirmation and Touch ID")
            }
        }
        .controlSize(.large)
    }

    private var facts: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 7) {
            fact("Server", row.serverName ?? "—")
            fact("Branch", [row.branch, row.shortCommit].compactMap { $0 }.joined(separator: " · ").ifEmpty("—"))
            fact("Last deploy", row.lastDeployAt.map { "\($0.formatted(date: .abbreviated, time: .shortened)) · \(row.lastDeployStatus ?? "")" } ?? "Never")
            if let duration = row.deploy?.durationSeconds, !row.isDeploying {
                fact("Took", DurationText.short(duration))
            }
            fact("SSL", sslText)
            fact("Maintenance", row.maintenanceMode ? "On" : "Off")
            if row.billingSuspended { fact("Billing", "Suspended") }
        }
        .font(.system(size: 12))
    }

    private func fact(_ key: String, _ value: String) -> some View {
        GridRow {
            Text(key)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.leading)
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    private var sslText: String {
        guard row.sslEnabled else { return "Off" }
        return row.sslDaysLeft.map { "\($0) days left" } ?? "On"
    }

    private var response: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionHeader(title: "Response time · recent checks", symbol: "waveform.path.ecg", tint: Vivid.pink)
                if (model.data.sparklines[row.id]?.count ?? 0) > 1 { ExpandChartButton { responseExpanded = true } }
            }
            Sparkline(points: model.data.sparklines[row.id] ?? [], color: Vivid.pink, reveal: false)
                .frame(height: 56)
            Text(responseCaption)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var responseCaption: String {
        var parts: [String] = []
        if let p95 = row.p95 { parts.append("p95 \(p95) ms") }
        if let uptime = row.uptimePercent { parts.append("uptime \(uptime)%") }
        return parts.isEmpty ? "Not monitored" : parts.joined(separator: " · ")
    }

    private var more: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "More", symbol: "ellipsis.circle.fill", tint: Vivid.slate)
            HStack(spacing: 6) {
                Button("Site Logs") { environment.open(.siteLogs(siteID: row.id)) }
                Button(row.maintenanceMode ? "End Maintenance…" : "Maintenance…") {
                    let id = row.id
                    let enable = !row.maintenanceMode
                    Task { await executor.setMaintenance(siteID: id, enable: enable) }
                }
                Button("Web Panel") { WebPanel.open(.site(id: row.id)) }
            }
            .controlSize(.small)
            Text("Config, SSL, Workers, Logs and Artisan are on the site page.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }
}

