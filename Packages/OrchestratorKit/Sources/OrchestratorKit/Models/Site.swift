import Foundation

/// `GET /api/sites` (array) and `GET /api/sites/:id` (object).
///
/// The list endpoint additionally carries `sslDaysLeft`, `sslExpiresAt`,
/// `enforcementLevel`, `billingSuspended` and `billingPastDue`; the detail endpoint
/// does not. Everything that varies between the two is optional.
public struct Site: Identifiable, Codable, Hashable, Sendable {
    public var id: Int
    public var name: String
    public var domain: String
    public var serverId: Int?
    public var phpVersion: String?
    public var dbName: String?
    public var dbUser: String?
    public var sslEnabled: Bool
    public var rootPath: String?
    public var status: String
    public var repoUrl: String?
    public var branch: String?
    public var webhookToken: String?
    public var preDeploy: String?
    public var postDeploy: String?
    public var healthCheck: Bool
    public var healthCheckUrl: String?
    public var runTests: Bool
    public var testCommand: String?
    public var testFailureMode: String?
    public var testTimeout: Int?
    public var testUseSqlite: Bool
    public var deployQueued: Bool
    public var maintenanceMode: Bool
    public var uptimeMonitor: Bool
    public var statusPageEnabled: Bool
    public var secBasicAuth: Bool
    public var secBasicUser: String?
    public var secIpMode: String?
    public var secIpList: String?
    public var pinned: Bool
    public var disabled: Bool
    public var tags: String?
    public var notes: String?
    public var createdAt: Date?
    public var updatedAt: Date?

    /// Recent deploys. NOTE: the server embeds the *entire* deploy log in each entry
    /// (100 KB+). `Deployment` deliberately has no `log` property so nothing is retained.
    public var deployments: [Deployment]?

    public var hasGitToken: Bool
    public var sslDaysLeft: Int?
    public var sslExpiresAt: Date?
    public var enforcementLevel: String?
    public var billingSuspended: Bool
    public var billingPastDue: Bool

    // MARK: - Derived

    /// Billing state outranks the `status` column — a suspended site is never green.
    public var tone: StatusTone {
        StatusTone.forSite(
            status: status,
            billingSuspended: billingSuspended,
            billingPastDue: billingPastDue,
            disabled: disabled
        )
    }

    /// What the badge says, taking billing and maintenance into account.
    public var statusLabel: String {
        if billingSuspended { return "suspended" }
        if disabled { return "disabled" }
        if maintenanceMode { return "maintenance" }
        if billingPastDue { return "past due" }
        return status
    }

    public var tagList: [String] { EmbeddedJSON.stringArray(from: tags) }

    public var lastDeployment: Deployment? { deployments?.first }

    public var sslTone: StatusTone {
        guard sslEnabled else { return .neutral }
        guard let days = sslDaysLeft else { return .neutral }
        if days <= 7 { return .critical }
        if days <= 21 { return .warning }
        return .good
    }

    public var displayURL: URL? { URL(string: "https://\(domain)") }

    /// Free-text haystack for the sites search field.
    public var searchHaystack: String {
        ([name, domain, status, phpVersion ?? "", branch ?? ""] + tagList)
            .joined(separator: " ")
            .lowercased()
    }
}

/// One deploy. `log` is intentionally absent — see `Site.deployments`.
public struct Deployment: Identifiable, Codable, Hashable, Sendable {
    public var id: Int
    public var siteId: Int
    public var commit: String?
    public var branch: String?
    public var status: String
    public var comment: String?
    public var testResult: String?
    public var testsPassed: Int?
    public var testsFailed: Int?
    public var testsTotal: Int?
    public var testDurationMs: Int?
    public var createdAt: Date?

    public var tone: StatusTone { StatusTone(status: status) }

    public var shortCommit: String {
        let value = String((commit ?? "").prefix(7))
        return value.isEmpty ? "—" : value
    }

    public var testSummary: String? {
        guard let total = testsTotal, total > 0 else { return nil }
        let passed = testsPassed ?? 0
        let failed = testsFailed ?? 0
        var text = "\(passed)/\(total) passed"
        if failed > 0 { text += " · \(failed) failed" }
        if let ms = testDurationMs { text += " · \(Durations.milliseconds(ms))" }
        return text
    }

    public var testTone: StatusTone { StatusTone(status: testResult) }
}

public struct SiteTagsResponse: Decodable, Sendable {
    public var tags: [String]
}

/// `GET /api/monitor/health-score/:siteId`
public struct HealthScore: Decodable, Sendable, Hashable {
    public struct Breakdown: Decodable, Sendable, Hashable {
        public var uptime: Int?
        public var deploy: Int?
        public var ssl: Int?
        public var maintenance: Int?
    }

    public var score: Int
    public var suspended: Bool
    public var enforcementLevel: String?
    public var breakdown: Breakdown?

    public var tone: StatusTone {
        if suspended { return .critical }
        switch score {
        case 85...:   return .good
        case 60..<85: return .warning
        default:      return .critical
        }
    }
}
