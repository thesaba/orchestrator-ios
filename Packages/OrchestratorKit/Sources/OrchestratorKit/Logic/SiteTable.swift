import Foundation

/// The filter above the Mac app's site table.
public enum SiteFilter: String, CaseIterable, Sendable, Identifiable {
    case all = "All"
    case production = "Production"
    case staging = "Staging"
    case problems = "Problems"

    public var id: String { rawValue }
}

/// One row of the site table, with everything its columns and inspector show.
public struct SiteTableRow: Sendable, Hashable, Identifiable {
    public var id: Int
    public var name: String
    public var domain: String
    public var mark: HealthMark
    /// "Up", "Down", "Deploying", "Disabled".
    public var label: String
    public var serverName: String?
    public var branch: String?
    public var shortCommit: String?
    public var lastDeployAt: Date?
    public var lastDeployStatus: String?
    public var lastDeploymentID: Int?
    public var deploy: DeployLogSummary?
    public var uptimePercent: Int?
    public var p95: Int?
    public var sslEnabled: Bool
    public var sslDaysLeft: Int?
    public var isStaging: Bool
    public var maintenanceMode: Bool
    public var disabled: Bool
    public var billingSuspended: Bool

    public var isDeploying: Bool { mark == .deploying }
    public var lastDeployFailed: Bool { (lastDeployStatus ?? "").lowercased() == "failed" }

    /// Text for the "Last deploy" column.
    public func lastDeployText(now: Date = .now) -> String {
        if isDeploying {
            if let step = deploy?.currentStep, let total = deploy?.totalSteps ?? Optional(step.total) {
                return "Deploying \(step.number)/\(total)"
            }
            return "Deploying"
        }
        guard let date = lastDeployAt else { return "Never" }
        return lastDeployFailed ? "Failed · \(RelativeTime.ago(date, now: now))" : RelativeTime.ago(date, now: now)
    }
}

/// Builds the site table. Pure, so it is unit-tested.
public enum SiteTable {
    /// - Parameters:
    ///   - sslWarningDays: certificates with this many days left or fewer count as a problem.
    public static func rows(overview: FleetOverview,
                            listings: [SiteListing]?,
                            servers: [FleetServer],
                            apm: APMOverview?,
                            filter: SiteFilter = .all,
                            search: String = "",
                            sslWarningDays: Int = 14) -> [SiteTableRow] {
        let listingByID = Dictionary((listings ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let serverByID = Dictionary(servers.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let localServer = servers.first(where: \.isLocal)?.name
        let apmBySite = Dictionary((apm?.sites ?? []).map { ($0.siteId, $0) }, uniquingKeysWith: { first, _ in first })

        let all = overview.sites.map { site -> SiteTableRow in
            let listing = listingByID[site.id]
            let serverName: String?
            if let listing {
                serverName = listing.serverId.flatMap { serverByID[$0] } ?? (listing.serverId == nil ? localServer : nil)
            } else {
                serverName = nil
            }
            let stats = apmBySite[site.id]
            return SiteTableRow(
                id: site.id, name: site.name, domain: site.domain, mark: site.mark, label: site.label,
                serverName: serverName, branch: site.branch, shortCommit: site.shortCommit,
                lastDeployAt: site.lastDeployAt, lastDeployStatus: site.lastDeployStatus,
                lastDeploymentID: site.lastDeploymentID, deploy: site.deploy,
                uptimePercent: stats?.uptimePct, p95: stats?.p95,
                sslEnabled: listing?.sslEnabled ?? false, sslDaysLeft: listing?.sslDaysLeft,
                isStaging: listing?.isStaging ?? false,
                maintenanceMode: listing?.maintenanceMode ?? false,
                disabled: listing?.disabled ?? false,
                billingSuspended: listing?.billingSuspended ?? false)
        }

        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return all.filter { row in
            switch filter {
            case .all:        break
            case .production: if row.isStaging { return false }
            case .staging:    if !row.isStaging { return false }
            case .problems:   if !hasProblem(row, sslWarningDays: sslWarningDays) { return false }
            }
            guard !query.isEmpty else { return true }
            return [row.name, row.domain, row.branch ?? "", row.serverName ?? ""]
                .contains { $0.lowercased().contains(query) }
        }
    }

    /// Down, warning, failed last deploy, certificate close to expiry, maintenance or suspended.
    public static func hasProblem(_ row: SiteTableRow, sslWarningDays: Int = 14) -> Bool {
        if row.mark == .failure || row.mark == .warning { return true }
        if row.lastDeployFailed || row.maintenanceMode || row.billingSuspended { return true }
        if row.sslEnabled, let days = row.sslDaysLeft, days <= sslWarningDays { return true }
        return false
    }
}
