import Foundation

/// Turns the raw read endpoints into a `FleetOverview`. Pure, so it is unit-tested.
///
/// Rules:
/// - A server is **failure** when its agent is offline or it has an open `offline` alert,
///   **warning** with any other open alert, **unknown** without fresh metrics, otherwise
///   **healthy**.
/// - A site is **deploying** when its newest deployment runs, **failure** when the uptime
///   check says down, **unknown** when it is not monitored or disabled, otherwise healthy.
/// - Attention items are open fleet alerts, certificates within `sslWarningDays` of expiry
///   (or failing their check) and sites that are down.
public struct StatusAggregator: Sendable {
    /// Certificates with this many days left or fewer raise an alert.
    public var sslWarningDays: Int
    /// Metrics older than this count as "no data" unless the agent is online.
    public var staleAfter: TimeInterval

    public init(sslWarningDays: Int = 14, staleAfter: TimeInterval = 15 * 60) {
        self.sslWarningDays = sslWarningDays
        self.staleAfter = staleAfter
    }

    public func overview(servers: [FleetServer],
                         alerts: [FleetAlertEvent],
                         certificates: [SSLOverview.Entry],
                         uptime: [UptimeOverview.Entry],
                         sites: [SiteListing]?,
                         now: Date = .now) -> FleetOverview {
        var result = FleetOverview()

        let openAlerts = alerts.filter(\.isActive)
        let alertsByServer = Dictionary(grouping: openAlerts, by: \.serverId)

        // Servers
        result.servers = servers
            .map { serverStatus($0, alerts: alertsByServer[$0.id] ?? [], now: now) }
            .sorted { ($0.mark, $0.server.name.lowercased()) < ($1.mark, $1.server.name.lowercased()) }
        for status in result.servers {
            result.serverCounts.total += 1
            switch status.mark {
            case .healthy:              result.serverCounts.healthy += 1
            case .warning:              result.serverCounts.warning += 1
            case .failure:              result.serverCounts.failure += 1
            case .unknown, .deploying:  result.serverCounts.unknown += 1
            }
        }

        // Sites
        result.sites = siteStatuses(uptime: uptime, sites: sites)
        for site in result.sites {
            result.siteCounts.total += 1
            switch site.mark {
            case .deploying: result.siteCounts.deploying += 1
            case .failure:   result.siteCounts.down += 1
            case .healthy:   result.siteCounts.up += 1
            default:         break
            }
        }

        // Attention
        var attention: [AttentionItem] = openAlerts
            .sorted { $0.startedAt > $1.startedAt }
            .map { alert in
                AttentionItem(
                    id: "alert-\(alert.id)",
                    subject: .server(id: alert.serverId, alertID: alert.id, kind: alert.kind),
                    severity: FleetAlertKind.isCritical(kind: alert.kind) ? .failure : .warning,
                    title: FleetAlertKind.headline(kind: alert.kind, value: alert.value, message: alert.message),
                    source: alert.serverName,
                    since: alert.startedAt,
                    category: FleetAlertKind.category(kind: alert.kind)
                )
            }

        for site in result.sites where site.mark == .failure {
            attention.append(AttentionItem(
                id: "down-\(site.id)", subject: .siteDown(siteID: site.id), severity: .failure,
                title: "Site down", source: site.domain, category: "down"))
        }

        for entry in certificates.sorted(by: { ($0.daysLeft ?? .max) < ($1.daysLeft ?? .max) }) {
            if let item = certificateItem(entry) { attention.append(item) }
        }

        // Worst first; equal severities keep their order (alerts newest first, then certificates).
        result.attention = attention.enumerated()
            .sorted { ($0.element.severity, $0.offset) < ($1.element.severity, $1.offset) }
            .map(\.element)
        return result
    }

    // MARK: - Servers

    public func serverStatus(_ server: FleetServer, alerts: [FleetAlertEvent], now: Date = .now) -> ServerStatus {
        let ordered = alerts.sorted {
            (FleetAlertKind.isCritical(kind: $0.kind) ? 0 : 1, $1.startedAt) < (FleetAlertKind.isCritical(kind: $1.kind) ? 0 : 1, $0.startedAt)
        }
        if server.agentStatus == "offline" || ordered.contains(where: { $0.kind == "offline" }) {
            return ServerStatus(server: server, mark: .failure, label: "Offline", alerts: ordered)
        }
        if let first = ordered.first {
            return ServerStatus(server: server, mark: .warning,
                                label: FleetAlertKind.shortLabel(kind: first.kind, value: first.value), alerts: ordered)
        }
        if server.activeAlerts > 0 {
            // Counted by the panel but not in the fetched alert page.
            return ServerStatus(server: server, mark: .warning, label: "\(server.activeAlerts) alerts")
        }
        guard let latest = server.latest else {
            let label = server.agentStatus == "pending" ? "Waiting for agent" : "No data"
            return ServerStatus(server: server, mark: .unknown, label: label)
        }
        if server.agentStatus != "online", now.timeIntervalSince(latest.at) > staleAfter {
            return ServerStatus(server: server, mark: .unknown, label: "No recent data")
        }
        return ServerStatus(server: server, mark: .healthy, label: "Healthy")
    }

    // MARK: - Sites

    func siteStatuses(uptime: [UptimeOverview.Entry], sites: [SiteListing]?) -> [SiteStatus] {
        let uptimeBySite = Dictionary(uptime.map { ($0.siteId, $0) }, uniquingKeysWith: { first, _ in first })
        var statuses: [SiteStatus]

        if let sites {
            statuses = sites.map { site in
                let check = uptimeBySite[site.id]
                let deployment = site.latestDeployment
                let (mark, label) = siteMark(listing: site, check: check)
                return SiteStatus(
                    id: site.id, name: site.name, domain: site.domain, mark: mark, label: label,
                    branch: deployment?.branch ?? site.branch,
                    shortCommit: deployment?.shortCommit,
                    lastDeployAt: deployment?.createdAt,
                    lastDeployStatus: deployment?.status,
                    lastDeploymentID: deployment?.id,
                    deploy: deployment?.log.map { DeployLogParser.parse($0, status: deployment?.status) }
                )
            }
        } else {
            statuses = uptime.map { check in
                let (mark, label) = siteMark(listing: nil, check: check)
                return SiteStatus(id: check.siteId, name: check.domain, domain: check.domain, mark: mark, label: label)
            }
        }

        // A running deploy first, then worst first, then most recently deployed.
        return statuses.sorted { lhs, rhs in
            if lhs.isDeploying != rhs.isDeploying { return lhs.isDeploying }
            if lhs.mark != rhs.mark { return lhs.mark < rhs.mark }
            return (lhs.lastDeployAt ?? .distantPast) > (rhs.lastDeployAt ?? .distantPast)
        }
    }

    func siteMark(listing: SiteListing?, check: UptimeOverview.Entry?) -> (HealthMark, String) {
        if listing?.isDeploying == true { return (.deploying, "Deploying") }
        if listing?.disabled == true { return (.unknown, "Disabled") }
        guard let check, check.monitoring else { return (.unknown, "Not monitored") }
        switch (check.status ?? "").lowercased() {
        case "up":   return (.healthy, "Up")
        case "down": return (.failure, "Down")
        default:     return (.unknown, check.status?.capitalized ?? "Unknown")
        }
    }

    // MARK: - Certificates

    func certificateItem(_ entry: SSLOverview.Entry) -> AttentionItem? {
        if let error = entry.error, !error.isEmpty {
            return AttentionItem(id: "ssl-\(entry.siteId)", subject: .certificate(siteID: entry.siteId),
                                 severity: .warning, title: "SSL check failed", source: entry.domain, category: "SSL")
        }
        guard let days = entry.daysLeft, days <= sslWarningDays else { return nil }
        let title: String
        switch days {
        case ..<0: title = "SSL expired"
        case 0:    title = "SSL expires today"
        case 1:    title = "SSL expires tomorrow"
        default:   title = "SSL expires in \(days) days"
        }
        return AttentionItem(id: "ssl-\(entry.siteId)", subject: .certificate(siteID: entry.siteId),
                             severity: days < 0 ? .failure : .warning, title: title,
                             source: entry.domain, category: "SSL")
    }
}
