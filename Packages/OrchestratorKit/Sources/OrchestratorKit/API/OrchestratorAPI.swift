import Foundation

/// Typed façade over `APIClient`. Feature code calls these instead of assembling paths,
/// so a route change is a one-line fix here rather than a hunt through views.
///
/// Phase 1 covers the read-only surface. Mutating calls arrive with Phase 2 and are kept
/// in a separate extension so it stays obvious which methods change server state.
public struct OrchestratorAPI: Sendable {
    public static let shared = OrchestratorAPI()

    /// Not `private`: `OrchestratorAPI+Actions.swift` extends this type from another file.
    public let client: APIClient

    public init(client: APIClient = .shared) {
        self.client = client
    }

    // MARK: - Account

    public func me() async throws -> User {
        try await client.get("/auth/me")
    }

    public func tokens() async throws -> [APIToken] {
        try await client.get("/tokens", as: APITokensResponse.self).tokens
    }

    // MARK: - Sites

    /// Heads-up: the server embeds full deploy logs in this payload (100 KB+ per deploy).
    /// `Deployment` drops the `log` field so nothing is retained, but the download is real.
    public func sites() async throws -> [Site] {
        try await client.get("/sites")
    }

    public func site(_ id: Int) async throws -> Site {
        try await client.get("/sites/\(id)")
    }

    public func siteTags() async throws -> [String] {
        try await client.get("/sites/tags", as: SiteTagsResponse.self).tags
    }

    public func healthScore(siteID: Int) async throws -> HealthScore {
        try await client.get("/monitor/health-score/\(siteID)")
    }

    public func siteSSL(siteID: Int) async throws -> SiteSSL {
        try await client.get("/sites/\(siteID)/ssl")
    }

    public func siteLogs(siteID: Int, level: String? = nil, search: String? = nil, lines: Int? = nil) async throws -> SiteLogsResponse {
        var query: [URLQueryItem] = []
        if let level, !level.isEmpty { query.append(URLQueryItem(name: "level", value: level)) }
        if let search, !search.isEmpty { query.append(URLQueryItem(name: "search", value: search)) }
        if let lines { query.append(URLQueryItem(name: "lines", value: String(lines))) }
        return try await client.get("/sites/\(siteID)/logs", query: query)
    }

    // MARK: - Monitoring

    public func systemSnapshot() async throws -> SystemSnapshot {
        try await client.get("/monitor/system")
    }

    /// `?hours=` is honoured; the panel defaults to 24.
    public func monitorHistory(hours: Int = 24) async throws -> MonitorHistory {
        try await client.get("/monitor/history", query: [URLQueryItem(name: "hours", value: String(hours))])
    }

    public func deployStats() async throws -> DeployStatsHistory {
        try await client.get("/monitor/stats/history")
    }

    public func processes(limit: Int = 8) async throws -> ProcessSnapshot {
        try await client.get("/monitor/processes", query: [URLQueryItem(name: "limit", value: String(limit))])
    }

    public func apm(hours: Int = 24) async throws -> APMOverview {
        try await client.get("/monitor/apm", query: [URLQueryItem(name: "hours", value: String(hours))])
    }

    public func services() async throws -> [ServiceStatus] {
        try await client.get("/monitor/services")
    }

    public func sslOverview() async throws -> SSLOverview {
        try await client.get("/monitor/ssl")
    }

    public func systemInfo() async throws -> SystemInfo {
        try await client.get("/system/info")
    }

    // MARK: - Uptime

    public func uptime() async throws -> UptimeOverview {
        try await client.get("/uptime")
    }

    public func uptimeHistory(siteID: Int) async throws -> UptimeHistory {
        try await client.get("/uptime/\(siteID)/history")
    }

    public func uptimeSparkline(siteID: Int) async throws -> UptimeSparkline {
        try await client.get("/uptime/\(siteID)/sparkline")
    }

    // MARK: - Inbox

    public func notifications() async throws -> NotificationsResponse {
        try await client.get("/notifications")
    }

    /// Grouped Laravel errors, newest first; only one site's when `siteID` is set.
    public func logErrors(siteID: Int? = nil) async throws -> LogErrorsResponse {
        let query = siteID.map { [URLQueryItem(name: "siteId", value: String($0))] } ?? []
        return try await client.get("/log-errors", query: query)
    }

    public func alertRules() async throws -> [AlertRule] {
        try await client.get("/alerts", as: AlertRulesResponse.self).rules
    }

    // MARK: - Billing (read-only in Phase 1)

    public func billingOverview() async throws -> BillingOverview {
        try await client.get("/billing/overview")
    }
}
