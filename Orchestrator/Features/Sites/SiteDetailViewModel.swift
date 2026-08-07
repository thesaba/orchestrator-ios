import Foundation

@MainActor
@Observable
final class SiteDetailViewModel {
    let siteID: Int

    private(set) var site: Site?
    private(set) var health: HealthScore?
    private(set) var ssl: SiteSSL?
    private(set) var sparkline: [UptimeSparkline.Point] = []
    private(set) var uptime24h: Int?

    private(set) var isLoading = false
    private(set) var loadError: APIError?
    private(set) var degradedSections: [String] = []

    private let api: OrchestratorAPI

    init(siteID: Int, initialSite: Site? = nil, api: OrchestratorAPI = .shared) {
        self.siteID = siteID
        self.site = initialSite
        self.api = api
    }

    var deployments: [Deployment] { site?.deployments ?? [] }

    var averageResponse: Int? {
        let values = sparkline.compactMap(\.ms)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / values.count
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        loadError = nil
        var degraded: [String] = []

        async let siteTask = api.site(siteID)
        async let healthTask = api.healthScore(siteID: siteID)
        async let sslTask = api.siteSSL(siteID: siteID)
        async let sparkTask = api.uptimeSparkline(siteID: siteID)
        async let historyTask = api.uptimeHistory(siteID: siteID)

        do {
            // The detail payload omits the billing columns the list endpoint adds, so keep
            // whatever we were handed on push and only overwrite the fields we just fetched.
            let fetched = try await siteTask
            site = merge(fetched, into: site)
        } catch {
            loadError = APIError.wrap(error)
        }
        do { health = try await healthTask } catch { degraded.append("Health score") }
        do { ssl = try await sslTask } catch { degraded.append("Certificate") }
        do { sparkline = try await sparkTask.points } catch { degraded.append("Response times") }
        do { uptime24h = try await historyTask.uptime24h } catch { degraded.append("Uptime") }

        degradedSections = degraded
    }

    /// `GET /api/sites/:id` does not return `sslDaysLeft`, `enforcementLevel`,
    /// `billingSuspended` or `billingPastDue`; the list row we navigated from does.
    private func merge(_ fetched: Site, into existing: Site?) -> Site {
        guard let existing else { return fetched }
        var result = fetched
        result.sslDaysLeft = fetched.sslDaysLeft ?? existing.sslDaysLeft
        result.sslExpiresAt = fetched.sslExpiresAt ?? existing.sslExpiresAt
        result.enforcementLevel = fetched.enforcementLevel ?? existing.enforcementLevel
        result.billingSuspended = fetched.billingSuspended || existing.billingSuspended
        result.billingPastDue = fetched.billingPastDue || existing.billingPastDue
        return result
    }
}
