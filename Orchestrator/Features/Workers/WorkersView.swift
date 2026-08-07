import SwiftUI

@MainActor
@Observable
final class WorkersViewModel {
    let site: Site

    private(set) var status: SupervisorStatus?
    private(set) var queue: QueueStats?
    private(set) var failedJobs: [FailedJob] = []
    private(set) var config: FileContents?

    private(set) var isLoading = false
    private(set) var degradedSections: [String] = []

    let runner = ActionRunner()

    private let api: OrchestratorAPI

    init(site: Site, api: OrchestratorAPI = .shared) {
        self.site = site
        self.api = api
    }

    var hasLoadedOnce = false

    var runningCount: Int { (status?.processes ?? []).filter { $0.tone == .good }.count }
    var processCount: Int { status?.processes.count ?? 0 }

    func load() async {
        isLoading = true
        defer { isLoading = false; hasLoadedOnce = true }

        var degraded: [String] = []

        async let statusTask = api.supervisorStatus(siteID: site.id)
        async let queueTask = api.queueStats(siteID: site.id)
        async let jobsTask = api.failedJobs(siteID: site.id)
        async let configTask = api.supervisorConfig(siteID: site.id)

        do { status = try await statusTask } catch { degraded.append("Workers") }
        do { queue = try await queueTask } catch { degraded.append("Queue") }
        do { failedJobs = try await jobsTask } catch { degraded.append("Failed jobs") }
        do { config = try await configTask } catch { degraded.append("Config") }

        degradedSections = degraded
    }

    /// Supervisor control is site-wide — the panel exposes no per-process variant.
    func control(_ action: OrchestratorAPI.SupervisorAction) async {
        await runner.run(action.rawValue, success: "\(action.title) sent to all workers.") { [self] in
            try await api.controlSupervisor(siteID: site.id, action: action)
        } onSuccess: { [self] in
            // Supervisor needs a moment before the new state is reportable.
            try? await Task.sleep(for: .seconds(1))
            await load()
        }
    }

    func retryAll() async {
        await runner.run("retry-all", success: "All failed jobs queued for retry.") { [self] in
            try await api.retryAllFailedJobs(siteID: site.id)
        } onSuccess: { [self] in await load() }
    }

    func retry(_ job: FailedJob) async {
        await runner.run("retry-\(job.id)", success: "Job queued for retry.") { [self] in
            try await api.retryFailedJob(siteID: site.id, jobID: job.routeID)
        } onSuccess: { [self] in await load() }
    }

    func delete(_ job: FailedJob) async {
        await runner.run("delete-\(job.id)", success: "Job deleted.") { [self] in
            try await api.deleteFailedJob(siteID: site.id, jobID: job.routeID)
        } onSuccess: { [self] in await load() }
    }

    func deleteAll() async {
        await runner.run("delete-all", success: "Failed jobs cleared.") { [self] in
            try await api.deleteAllFailedJobs(siteID: site.id)
        } onSuccess: { [self] in await load() }
    }
}

struct WorkersView: View {
    @State private var model: WorkersViewModel
    @State private var confirmation: Confirmation?

    enum Confirmation: Identifiable {
        case stopAll
        case deleteAllJobs
        case delete(FailedJob)

        var id: String {
            switch self {
            case .stopAll:            return "stop-all"
            case .deleteAllJobs:      return "delete-all"
            case .delete(let job):    return "delete-\(job.id)"
            }
        }
    }

    init(site: Site) {
        _model = State(initialValue: WorkersViewModel(site: site))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if !model.degradedSections.isEmpty {
                    InlineErrorBanner(message: "Could not load: \(model.degradedSections.joined(separator: ", ")).")
                }
                ActionFeedbackView(runner: model.runner)
                queueCard
                workersCard
                failedJobsCard
                if let config = model.config, !config.content.isEmpty { configCard(config) }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Workers")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.load() }
        .task { if !model.hasLoadedOnce { await model.load() } }
        .confirmationDialog(
            confirmationTitle,
            isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }),
            titleVisibility: .visible,
            presenting: confirmation
        ) { item in
            switch item {
            case .stopAll:
                Button("Stop all workers", role: .destructive) {
                    Task { await model.control(.stop) }
                }
            case .deleteAllJobs:
                Button("Delete all failed jobs", role: .destructive) {
                    Task { await model.deleteAll() }
                }
            case .delete(let job):
                Button("Delete job", role: .destructive) {
                    Task { await model.delete(job) }
                }
            }
            Button("Cancel", role: .cancel) { confirmation = nil }
        } message: { item in
            switch item {
            case .stopAll:
                Text("Queued jobs stop being processed until the workers are started again.")
            case .deleteAllJobs:
                Text("The failed jobs are removed permanently and cannot be retried afterwards.")
            case .delete:
                Text("This job is removed permanently and cannot be retried afterwards.")
            }
        }
    }

    private var confirmationTitle: String {
        switch confirmation {
        case .stopAll:       return "Stop workers on \(model.site.domain)?"
        case .deleteAllJobs: return "Delete every failed job?"
        case .delete:        return "Delete this failed job?"
        case nil:            return ""
        }
    }

    private var queueCard: some View {
        SectionCard("Queue", systemImage: "tray.full") {
            HStack(spacing: 12) {
                MetricTile(
                    title: "Pending",
                    value: model.queue?.pending.map(String.init) ?? "—",
                    caption: "waiting jobs",
                    tone: (model.queue?.pending ?? 0) > 100 ? .warning : .neutral
                )
                MetricTile(
                    title: "Failed",
                    value: model.queue?.failed.map(String.init) ?? "\(model.failedJobs.count)",
                    caption: "in failed_jobs",
                    tone: (model.queue?.failed ?? model.failedJobs.count) > 0 ? .critical : .good
                )
            }
        }
    }

    private var workersCard: some View {
        SectionCard(
            "Supervisor",
            systemImage: "gearshape.2",
            accessory: AnyView(
                Text("\(model.runningCount)/\(model.processCount) running")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            )
        ) {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Button {
                        Task { await model.control(.start) }
                    } label: {
                        Label("Start", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        Task { await model.control(.restart) }
                    } label: {
                        Label("Restart", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        confirmation = .stopAll
                    } label: {
                        Label("Stop", systemImage: "stop.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .font(.footnote)
                .disabled(model.runner.isRunning)

                if let processes = model.status?.processes, !processes.isEmpty {
                    Divider()
                    ForEach(processes) { process in
                        HStack {
                            StatusDot(tone: process.tone)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(process.name)
                                    .font(.callout.monospaced())
                                if let description = process.description {
                                    Text(description)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            Text(process.state.lowercased())
                                .font(.caption.weight(.medium))
                                .foregroundStyle(process.tone.color)
                        }
                    }
                } else {
                    Text("No worker processes are configured for this site.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var failedJobsCard: some View {
        SectionCard("Failed jobs", systemImage: "exclamationmark.arrow.circlepath") {
            if model.failedJobs.isEmpty {
                Text("No failed jobs.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        Button {
                            Task { await model.retryAll() }
                        } label: {
                            Label("Retry all", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button(role: .destructive) {
                            confirmation = .deleteAllJobs
                        } label: {
                            Label("Delete all", systemImage: "trash").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .font(.footnote)
                    .disabled(model.runner.isRunning)

                    Divider()

                    ForEach(model.failedJobs) { job in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(job.jobName ?? "Job")
                                    .font(.callout.weight(.medium))
                                Spacer()
                                Text(job.failedAt.relativeShortOrDash)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(job.exceptionHeadline)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                            HStack(spacing: 14) {
                                if let queue = job.queue {
                                    Text(queue)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Retry") { Task { await model.retry(job) } }
                                    .font(.caption)
                                Button("Delete", role: .destructive) { confirmation = .delete(job) }
                                    .font(.caption)
                            }
                            .disabled(model.runner.isRunning)
                        }
                        .padding(.vertical, 4)
                        if job.id != model.failedJobs.last?.id { Divider() }
                    }
                }
            }
        }
    }

    private func configCard(_ config: FileContents) -> some View {
        SectionCard("supervisor.conf", systemImage: "doc.plaintext") {
            ScrollView(.horizontal) {
                Text(config.content)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 220)
        }
    }
}
