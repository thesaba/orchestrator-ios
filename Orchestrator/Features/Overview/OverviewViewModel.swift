import Foundation

/// The overview aggregates seven independent endpoints. One of them failing should
/// grey out that card, not blank the whole screen — so failures are collected per
/// section and only `/sites` is treated as fatal.
@MainActor
@Observable
final class OverviewViewModel {
    private(set) var sites: [Site] = []
    private(set) var system: SystemSnapshot?
    private(set) var uptime: UptimeOverview?
    private(set) var ssl: SSLOverview?
    private(set) var inbox: NotificationsResponse?
    private(set) var logErrors: LogErrorsResponse?
    private(set) var billing: BillingOverview?

    private(set) var isLoading = false
    private(set) var fatalError: APIError?
    private(set) var degradedSections: [String] = []

    private let api: OrchestratorAPI

    init(api: OrchestratorAPI = .shared) {
        self.api = api
    }

    var hasLoadedOnce: Bool { !sites.isEmpty || fatalError != nil }

    // MARK: - Derived summaries

    var activeSites: Int { sites.filter { $0.tone == .good }.count }
    var attentionSites: [Site] { sites.filter { $0.tone == .critical || $0.tone == .warning } }
    var suspendedSites: Int { sites.filter(\.billingSuspended).count }
    var maintenanceSites: Int { sites.filter(\.maintenanceMode).count }

    var sitesDown: [UptimeOverview.Entry] {
        (uptime?.sites ?? []).filter { $0.monitoring && !$0.isUp }
    }

    var uptimeMonitored: Int { (uptime?.sites ?? []).filter(\.monitoring).count }

    /// Certificates worth worrying about, soonest first.
    var expiringCertificates: [SSLOverview.Entry] {
        (ssl?.sites ?? [])
            .filter { ($0.daysLeft ?? .max) <= 21 || $0.error != nil }
            .sorted { ($0.daysLeft ?? .max) < ($1.daysLeft ?? .max) }
    }

    var unreadNotifications: Int { inbox?.unread ?? inbox?.notifications.filter { !$0.read }.count ?? 0 }
    var openErrors: Int { logErrors?.unresolved ?? 0 }

    /// A named type rather than a tuple: labelled tuples do not survive `compactMap`
    /// inference, and `ForEach` wants a stable `Identifiable`.
    struct RecentDeploy: Identifiable, Hashable {
        let site: Site
        let deployment: Deployment
        var id: Int { deployment.id }
    }

    var recentDeployments: [RecentDeploy] {
        sites
            .compactMap { site in
                guard let deployment = site.lastDeployment else { return nil }
                return RecentDeploy(site: site, deployment: deployment)
            }
            .sorted { ($0.deployment.createdAt ?? .distantPast) > ($1.deployment.createdAt ?? .distantPast) }
            .prefix(5)
            .map { $0 }
    }

    // MARK: - Loading

    func load() async {
        isLoading = true
        defer { isLoading = false }

        fatalError = nil
        var degraded: [String] = []

        async let sitesTask = api.sites()
        async let systemTask = api.systemSnapshot()
        async let uptimeTask = api.uptime()
        async let sslTask = api.sslOverview()
        async let inboxTask = api.notifications()
        async let errorsTask = api.logErrors()
        async let billingTask = api.billingOverview()

        do { sites = try await sitesTask } catch { fatalError = APIError.wrap(error) }
        do { system = try await systemTask } catch { degraded.append("Server metrics") }
        do { uptime = try await uptimeTask } catch { degraded.append("Uptime") }
        do { ssl = try await sslTask } catch { degraded.append("Certificates") }
        do { inbox = try await inboxTask } catch { degraded.append("Notifications") }
        do { logErrors = try await errorsTask } catch { degraded.append("Errors") }
        do { billing = try await billingTask } catch { degraded.append("Billing") }

        degradedSections = degraded
    }
}
