import Foundation
import OrchestratorKit

@MainActor
@Observable
final class MonitorViewModel {
    private(set) var system: SystemSnapshot?
    private(set) var history: MonitorHistory?
    private(set) var services: [ServiceStatus] = []
    private(set) var processes: ProcessSnapshot?
    private(set) var apm: APMOverview?
    private(set) var deployStats: DeployStatsHistory?
    private(set) var info: SystemInfo?

    private(set) var isLoading = false
    private(set) var fatalError: APIError?
    private(set) var degradedSections: [String] = []

    private let api: OrchestratorAPI

    init(api: OrchestratorAPI = .shared) {
        self.api = api
    }

    var hasLoadedOnce: Bool { system != nil || fatalError != nil }

    /// ~1400 raw points per day would stall the chart; average into 120 buckets.
    var chartSamples: [MonitorHistory.Sample] { history?.downsampled(to: 120) ?? [] }

    var topProcesses: [ProcessSnapshot.Entry] {
        (processes?.services ?? [])
            .sorted { ($0.cpuPercent ?? 0) > ($1.cpuPercent ?? 0) }
            .prefix(8)
            .map { $0 }
    }

    var slowestSites: [APMOverview.SiteEntry] {
        (apm?.sites ?? []).sorted { ($0.p95 ?? 0) > ($1.p95 ?? 0) }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        fatalError = nil
        var degraded: [String] = []

        async let systemTask = api.systemSnapshot()
        async let historyTask = api.monitorHistory()
        async let servicesTask = api.services()
        async let processesTask = api.processes()
        async let apmTask = api.apm()
        async let deployTask = api.deployStats()
        async let infoTask = api.systemInfo()

        do { system = try await systemTask } catch { fatalError = APIError.wrap(error) }
        do { history = try await historyTask } catch { degraded.append("History") }
        do { services = try await servicesTask } catch { degraded.append("Services") }
        do { processes = try await processesTask } catch { degraded.append("Processes") }
        do { apm = try await apmTask } catch { degraded.append("Performance") }
        do { deployStats = try await deployTask } catch { degraded.append("Deploy stats") }
        do { info = try await infoTask } catch { degraded.append("System info") }

        degradedSections = degraded
    }
}
