import Foundation

/// `GET /api/sites` (array) and `GET /api/sites/:id` (object).
///
/// The list endpoint additionally carries `sslDaysLeft`, `sslExpiresAt`,
/// `enforcementLevel`, `billingSuspended` and `billingPastDue`; the detail endpoint
/// does not. Everything that varies between the two is optional.
struct Site: Identifiable, Codable, Hashable, Sendable {
    var id: Int
    var name: String
    var domain: String
    var serverId: Int?
    var phpVersion: String?
    var dbName: String?
    var dbUser: String?
    var sslEnabled: Bool
    var rootPath: String?
    var status: String
    var repoUrl: String?
    var branch: String?
    var webhookToken: String?
    var preDeploy: String?
    var postDeploy: String?
    var healthCheck: Bool
    var healthCheckUrl: String?
    var runTests: Bool
    var testCommand: String?
    var testFailureMode: String?
    var testTimeout: Int?
    var testUseSqlite: Bool
    var deployQueued: Bool
    var maintenanceMode: Bool
    var uptimeMonitor: Bool
    var statusPageEnabled: Bool
    var secBasicAuth: Bool
    var secBasicUser: String?
    var secIpMode: String?
    var secIpList: String?
    var pinned: Bool
    var disabled: Bool
    var tags: String?
    var notes: String?
    var createdAt: Date?
    var updatedAt: Date?

    /// Recent deploys. NOTE: the server embeds the *entire* deploy log in each entry
    /// (100 KB+). `Deployment` deliberately has no `log` property so nothing is retained.
    var deployments: [Deployment]?

    var hasGitToken: Bool
    var sslDaysLeft: Int?
    var sslExpiresAt: Date?
    var enforcementLevel: String?
    var billingSuspended: Bool
    var billingPastDue: Bool

    // MARK: - Derived

    /// Billing state outranks the `status` column — a suspended site is never green.
    var tone: StatusTone {
        StatusTone.forSite(
            status: status,
            billingSuspended: billingSuspended,
            billingPastDue: billingPastDue,
            disabled: disabled
        )
    }

    /// What the badge says, taking billing and maintenance into account.
    var statusLabel: String {
        if billingSuspended { return "suspended" }
        if disabled { return "disabled" }
        if maintenanceMode { return "maintenance" }
        if billingPastDue { return "past due" }
        return status
    }

    var tagList: [String] { EmbeddedJSON.stringArray(from: tags) }

    var lastDeployment: Deployment? { deployments?.first }

    var sslTone: StatusTone {
        guard sslEnabled else { return .neutral }
        guard let days = sslDaysLeft else { return .neutral }
        if days <= 7 { return .critical }
        if days <= 21 { return .warning }
        return .good
    }

    var displayURL: URL? { URL(string: "https://\(domain)") }

    /// Free-text haystack for the sites search field.
    var searchHaystack: String {
        ([name, domain, status, phpVersion ?? "", branch ?? ""] + tagList)
            .joined(separator: " ")
            .lowercased()
    }
}

/// One deploy. `log` is intentionally absent — see `Site.deployments`.
struct Deployment: Identifiable, Codable, Hashable, Sendable {
    var id: Int
    var siteId: Int
    var commit: String?
    var branch: String?
    var status: String
    var comment: String?
    var testResult: String?
    var testsPassed: Int?
    var testsFailed: Int?
    var testsTotal: Int?
    var testDurationMs: Int?
    var createdAt: Date?

    var tone: StatusTone { StatusTone(status: status) }

    var shortCommit: String {
        let value = String((commit ?? "").prefix(7))
        return value.isEmpty ? "—" : value
    }

    var testSummary: String? {
        guard let total = testsTotal, total > 0 else { return nil }
        let passed = testsPassed ?? 0
        let failed = testsFailed ?? 0
        var text = "\(passed)/\(total) passed"
        if failed > 0 { text += " · \(failed) failed" }
        if let ms = testDurationMs { text += " · \(Durations.milliseconds(ms))" }
        return text
    }

    var testTone: StatusTone { StatusTone(status: testResult) }
}

struct SiteTagsResponse: Decodable, Sendable {
    var tags: [String]
}

/// `GET /api/monitor/health-score/:siteId`
struct HealthScore: Decodable, Sendable, Hashable {
    struct Breakdown: Decodable, Sendable, Hashable {
        var uptime: Int?
        var deploy: Int?
        var ssl: Int?
        var maintenance: Int?
    }

    var score: Int
    var suspended: Bool
    var enforcementLevel: String?
    var breakdown: Breakdown?

    var tone: StatusTone {
        if suspended { return .critical }
        switch score {
        case 85...:   return .good
        case 60..<85: return .warning
        default:      return .critical
        }
    }
}
