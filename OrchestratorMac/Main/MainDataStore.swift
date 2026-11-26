import Foundation
import Observation
import OrchestratorKit

/// The extra read-only data the main window needs on top of `MonitorStore`: deploy counts,
/// response-time percentiles, fleet resource history and per-site response sparklines.
///
/// Every request is a GET, and nothing loads while the window is hidden.
@MainActor
@Observable
final class MainDataStore {
    private(set) var deployStats: DeployStatsHistory?
    private(set) var apm: APMOverview?
    /// Fleet-average CPU, RAM and disk per range.
    private(set) var resources: [MetricsRange: [ResourcePoint]] = [:]
    private(set) var isLoadingResources = false
    /// Response times in ms, oldest first, per site.
    private(set) var sparklines: [Int: [Double]] = [:]

    /// The range the Dashboard charts show.
    var range: MetricsRange = .day {
        didSet { if range != oldValue { loadResources(force: false) } }
    }

    /// Set by the window controller when the window is on screen.
    var isVisible = false {
        didSet {
            guard isVisible != oldValue else { return }
            isVisible ? startLoop() : stopLoop()
        }
    }

    @ObservationIgnored private let api: OrchestratorAPI
    @ObservationIgnored private let store: MonitorStore
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var summariesUpdated: Date?
    @ObservationIgnored private var resourcesUpdated: [MetricsRange: Date] = [:]
    @ObservationIgnored private var sparklinesUpdated: [Int: Date] = [:]
    @ObservationIgnored private var sparklinesLoading: Set<Int> = []

    private static let summaryInterval: TimeInterval = 60
    private static let resourceInterval: TimeInterval = 5 * 60
    private static let sparklineInterval: TimeInterval = 5 * 60

    init(store: MonitorStore, api: OrchestratorAPI = .shared) {
        self.store = store
        self.api = api
    }

    /// The toolbar's Refresh button.
    func refreshAll() {
        summariesUpdated = nil
        resourcesUpdated = [:]
        sparklinesUpdated = [:]
        Task { await loadSummaries() }
        loadResources(force: true)
    }

    /// Clears everything on sign-out.
    func reset() {
        deployStats = nil
        apm = nil
        resources = [:]
        sparklines = [:]
        summariesUpdated = nil
        resourcesUpdated = [:]
        sparklinesUpdated = [:]
    }

    // MARK: - Loop

    private func startLoop() {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.loadSummaries()
                self.loadResources(force: false)
                // Retries soon while the fleet list has not arrived yet, then every 30 s.
                let waiting = self.resources[self.range] == nil
                try? await Task.sleep(for: .seconds(waiting ? 3 : 30))
            }
        }
    }

    private func stopLoop() {
        loop?.cancel()
        loop = nil
    }

    private func isDue(_ date: Date?, every interval: TimeInterval) -> Bool {
        guard let date else { return true }
        return Date.now.timeIntervalSince(date) >= interval
    }

    // MARK: - Deploy counts and percentiles

    private func loadSummaries() async {
        guard isDue(summariesUpdated, every: Self.summaryInterval) else { return }
        summariesUpdated = .now
        async let stats = try? api.deployStats()
        async let percentiles = try? api.apm(hours: 24)
        if let value = await stats { deployStats = value }
        if let value = await percentiles { apm = value }
    }

    // MARK: - Fleet resources

    private func loadResources(force: Bool) {
        let range = self.range
        guard !isLoadingResources else { return }
        // Short ranges change faster, so they are fetched more often.
        let interval = min(Self.resourceInterval, range.duration / 12)
        guard force || isDue(resourcesUpdated[range], every: interval) else { return }
        let serverIDs = store.servers.map(\.id)
        guard !serverIDs.isEmpty else { return }

        isLoadingResources = true
        resourcesUpdated[range] = .now
        let api = self.api
        Task {
            defer { isLoadingResources = false }
            let histories = await withTaskGroup(of: [FleetMetricsHistory.Point]?.self) { group in
                for id in serverIDs {
                    group.addTask { try? await api.fleetMetrics(serverID: id, range: range).points }
                }
                var all: [[FleetMetricsHistory.Point]] = []
                for await points in group { if let points { all.append(points) } }
                return all
            }
            let end = Date.now
            resources[range] = ResourceAverager.average(histories, from: end.addingTimeInterval(-range.duration),
                                                        to: end, buckets: range.buckets)
        }
    }

    // MARK: - Sparklines

    /// Loads response-time sparklines for these sites when missing or older than 5 minutes.
    func requestSparklines(for siteIDs: [Int]) {
        guard isVisible else { return }
        let api = self.api
        for id in siteIDs where !sparklinesLoading.contains(id)
            && isDue(sparklinesUpdated[id], every: Self.sparklineInterval) {
            sparklinesLoading.insert(id)
            sparklinesUpdated[id] = .now
            Task {
                defer { sparklinesLoading.remove(id) }
                guard let points = try? await api.uptimeSparkline(siteID: id).points else { return }
                sparklines[id] = points.sorted { $0.at < $1.at }.compactMap { $0.ms.map(Double.init) }
            }
        }
    }
}
