import Foundation
import Observation
import OrchestratorKit

/// The latest read-only picture of the fleet. Every request here is a GET.
///
/// Each source is fetched independently: when one fails, its previous value is kept and the
/// failure is reported in `lastError`, so the popover keeps showing the last good data.
@MainActor
@Observable
final class MonitorStore {
    private(set) var overview = FleetOverview()
    private(set) var servers: [FleetServer] = []
    private(set) var alerts: [FleetAlertEvent] = []
    private(set) var certificates: [SSLOverview.Entry] = []
    private(set) var uptime: [UptimeOverview.Entry] = []
    /// `nil` until the (slow) site list has loaded once.
    private(set) var siteListings: [SiteListing]?
    private(set) var notifications: [AppNotification] = []

    /// When the last refresh finished with every source answering.
    private(set) var lastUpdated: Date?
    /// When the site list was last fetched.
    private(set) var siteListUpdated: Date?
    /// Why the last refresh was incomplete, if it was.
    private(set) var lastError: String?
    private(set) var isRefreshing = false
    /// False until the first refresh has finished; drives the redacted first-load state.
    private(set) var hasLoaded = false

    /// Called after each refresh so notifications can compare old and new data.
    @ObservationIgnored var onRefresh: (() -> Void)?

    @ObservationIgnored private let api: OrchestratorAPI
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private var aggregator: StatusAggregator {
        StatusAggregator(sslWarningDays: AppSettings.sslWarningDays)
    }

    init(settings: AppSettings, api: OrchestratorAPI = .shared) {
        self.settings = settings
        self.api = api
    }

    /// True when the menu bar should show the neutral "unknown" mark.
    var isStale: Bool { lastError != nil || !hasLoaded }

    func site(id: Int) -> SiteStatus? { overview.sites.first { $0.id == id } }
    func server(id: Int) -> ServerStatus? { overview.servers.first { $0.id == id } }

    // MARK: - Refresh

    func refresh(includeSiteList: Bool) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        async let serversResult = capture { try await self.api.fleetServers().servers }
        async let alertsResult = capture { try await self.api.fleetAlerts(active: true, limit: 200) }
        async let certificatesResult = capture { try await self.api.sslOverview().sites }
        async let uptimeResult = capture { try await self.api.uptime().sites }
        async let notificationsResult = capture { try await self.api.notifications().notifications }
        async let sitesResult: Result<[SiteListing], Error>? = includeSiteList
            ? capture { try await self.api.siteListings() }
            : nil

        var failures: [String] = []
        func apply<T>(_ result: Result<T, Error>, label: String, _ assign: (T) -> Void) {
            switch result {
            case .success(let value): assign(value)
            case .failure(let error): failures.append(Self.describe(error, source: label))
            }
        }

        apply(await serversResult, label: "servers") { servers = $0 }
        apply(await alertsResult, label: "alerts") { alerts = $0 }
        apply(await certificatesResult, label: "certificates") { certificates = $0 }
        apply(await uptimeResult, label: "uptime") { uptime = $0 }
        apply(await notificationsResult, label: "notifications") { notifications = $0 }
        if let result = await sitesResult {
            apply(result, label: "sites") { listings in
                siteListings = listings
                siteListUpdated = .now
            }
        }

        overview = aggregator.overview(servers: servers, alerts: alerts, certificates: certificates,
                                       uptime: uptime, sites: siteListings)
        hasLoaded = true
        if failures.isEmpty {
            lastUpdated = .now
            lastError = nil
        } else {
            lastError = Self.summarize(failures)
        }
        onRefresh?()
    }

    /// Clears everything on sign-out.
    func reset() {
        overview = FleetOverview()
        servers = []
        alerts = []
        certificates = []
        uptime = []
        siteListings = nil
        notifications = []
        lastUpdated = nil
        siteListUpdated = nil
        lastError = nil
        hasLoaded = false
    }

    // MARK: - Errors

    /// `@concurrent` so decoding large payloads (the site list) happens off the main actor.
    @concurrent
    private nonisolated func capture<T: Sendable>(_ work: @Sendable () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await work()) } catch { return .failure(error) }
    }

    private static func describe(_ error: Error, source: String) -> String {
        let apiError = APIError.wrap(error)
        if case .forbidden = apiError, source == "servers" || source == "alerts" {
            return "Fleet monitoring needs an admin account"
        }
        return apiError.errorDescription ?? "Request failed"
    }

    private static func summarize(_ failures: [String]) -> String {
        var unique: [String] = []
        for failure in failures where !unique.contains(failure) { unique.append(failure) }
        return unique.joined(separator: " · ")
    }
}
