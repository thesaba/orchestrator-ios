import Foundation

/// What the Mac app's Dashboard shows, derived from the monitoring data. Pure, so it is
/// unit-tested; the view only lays it out.
public struct DashboardSummary: Sendable, Hashable {
    public struct Tile: Sendable, Hashable, Identifiable {
        public enum Kind: String, Sendable, Hashable { case servers, sites, alerts, deploys }
        public var kind: Kind
        public var caption: String
        public var value: String
        public var detail: String
        /// Set when the value should be drawn in a status colour.
        public var emphasis: HealthMark?

        public var id: Kind { kind }
    }

    /// A site's newest deployment, for the deploy timeline.
    public struct RecentDeploy: Sendable, Hashable, Identifiable {
        public enum Outcome: Sendable, Hashable { case running, succeeded, failed, other(String) }
        public var siteID: Int
        public var domain: String
        public var branch: String?
        public var shortCommit: String?
        public var startedAt: Date?
        public var outcome: Outcome
        public var durationSeconds: Int?
        /// Only while running.
        public var currentStep: DeployStep?
        public var totalSteps: Int?
        public var progress: Double?

        public var id: Int { siteID }
    }

    /// One site of "Uptime & response".
    public struct UptimeRow: Sendable, Hashable, Identifiable {
        public var siteID: Int
        public var domain: String
        public var mark: HealthMark
        /// 0…100 over the APM window, when known.
        public var uptimePercent: Int?
        public var p95: Int?
        public var responseMs: Int?

        public var id: Int { siteID }
    }

    public var tiles: [Tile] = []
    public var recentDeploys: [RecentDeploy] = []
    public var uptimeRows: [UptimeRow] = []

    public init() {}

    /// - Parameters:
    ///   - deployLimit: how many deployments the timeline shows.
    ///   - uptimeLimit: how many sites "Uptime & response" shows, worst first.
    public static func make(overview: FleetOverview,
                            deployStats: DeployStatsHistory?,
                            apm: APMOverview?,
                            uptime: [UptimeOverview.Entry],
                            deployLimit: Int = 6,
                            uptimeLimit: Int = 6,
                            now: Date = .now,
                            calendar: Calendar = .current) -> DashboardSummary {
        var summary = DashboardSummary()

        // Tiles
        let servers = overview.serverCounts
        let sites = overview.siteCounts
        let alerts = overview.attention
        let today = deployStats?.days.first { calendar.isDate($0.date, inSameDayAs: now) }
        let running = sites.deploying
        var deployParts: [String] = []
        if let today {
            deployParts.append("\(today.success) succeeded")
            if today.failed > 0 { deployParts.append("\(today.failed) failed") }
        }
        if running > 0 { deployParts.append("\(running) running") }

        summary.tiles = [
            Tile(kind: .servers, caption: "Servers",
                 value: servers.total == 0 ? "0" : "\(servers.healthy) / \(servers.total)",
                 detail: servers.total == 0 ? "No servers" : servers.breakdown,
                 emphasis: servers.failure > 0 ? .failure : nil),
            Tile(kind: .sites, caption: "Sites",
                 value: sites.total == 0 ? "0" : "\(sites.up) / \(sites.total)",
                 detail: sites.total == 0 ? "No sites" : sites.breakdown,
                 emphasis: sites.down > 0 ? .failure : nil),
            Tile(kind: .alerts, caption: "Open alerts", value: "\(alerts.count)",
                 detail: overview.alertBreakdown,
                 emphasis: alerts.contains { $0.severity == .failure } ? .failure : (alerts.isEmpty ? nil : .warning)),
            Tile(kind: .deploys, caption: "Deploys today",
                 value: today.map { "\($0.total + running)" } ?? (running > 0 ? "\(running)" : "—"),
                 detail: deployParts.isEmpty ? (today == nil ? "No data yet" : "None yet") : deployParts.joined(separator: " · "),
                 emphasis: (today?.failed ?? 0) > 0 ? .warning : nil)
        ]

        // Deploy timeline: running first, then newest first.
        summary.recentDeploys = overview.sites
            .filter { $0.lastDeployAt != nil || $0.isDeploying }
            .sorted { lhs, rhs in
                if lhs.isDeploying != rhs.isDeploying { return lhs.isDeploying }
                return (lhs.lastDeployAt ?? .distantPast) > (rhs.lastDeployAt ?? .distantPast)
            }
            .prefix(deployLimit)
            .map { site in
                let outcome: RecentDeploy.Outcome
                if site.isDeploying {
                    outcome = .running
                } else {
                    switch (site.lastDeployStatus ?? "").lowercased() {
                    case "success", "succeeded": outcome = .succeeded
                    case "failed", "error":      outcome = .failed
                    case "running":              outcome = .running
                    case let other:              outcome = .other(other)
                    }
                }
                return RecentDeploy(
                    siteID: site.id, domain: site.domain, branch: site.branch, shortCommit: site.shortCommit,
                    startedAt: site.lastDeployAt, outcome: outcome,
                    durationSeconds: site.isDeploying ? nil : site.deploy?.durationSeconds,
                    currentStep: site.isDeploying ? site.deploy?.currentStep : nil,
                    totalSteps: site.deploy?.totalSteps,
                    progress: site.isDeploying ? site.deploy?.progress : nil)
            }

        // Uptime & response: monitored sites, worst first.
        let apmBySite = Dictionary((apm?.sites ?? []).map { ($0.siteId, $0) }, uniquingKeysWith: { first, _ in first })
        let markBySite = Dictionary(overview.sites.map { ($0.id, $0.mark) }, uniquingKeysWith: { first, _ in first })
        summary.uptimeRows = uptime
            .filter(\.monitoring)
            .map { entry in
                let stats = apmBySite[entry.siteId]
                let mark: HealthMark
                if !entry.isUp, entry.status != nil {
                    mark = .failure
                } else if let percent = stats?.uptimePct, percent < 99 {
                    mark = .warning
                } else {
                    mark = markBySite[entry.siteId] == .deploying ? .deploying : (entry.isUp ? .healthy : .unknown)
                }
                return UptimeRow(siteID: entry.siteId, domain: entry.domain, mark: mark,
                                 uptimePercent: stats?.uptimePct, p95: stats?.p95, responseMs: entry.responseMs)
            }
            .sorted { lhs, rhs in
                if lhs.mark != rhs.mark { return lhs.mark < rhs.mark }
                if (lhs.uptimePercent ?? 100) != (rhs.uptimePercent ?? 100) { return (lhs.uptimePercent ?? 100) < (rhs.uptimePercent ?? 100) }
                return (lhs.p95 ?? 0) > (rhs.p95 ?? 0)
            }
            .prefix(uptimeLimit)
            .map { $0 }

        return summary
    }
}
