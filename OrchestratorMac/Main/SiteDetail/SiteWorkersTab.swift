import OrchestratorKit
import SwiftUI

/// Supervisor workers, the queue, failed jobs and the scheduler. Start, stop and restart act
/// on every worker of the site; the panel has no per-process control.
struct SiteWorkersTab: View {
    let environment: AppEnvironment
    let siteID: Int

    @State private var status: SupervisorStatus?
    @State private var queue: QueueStats?
    @State private var failed: [FailedJob] = []
    @State private var scheduler: SchedulerInfo?
    @State private var hasLoaded = false
    @State private var isWorking = false

    private var executor: CommandExecutor { environment.executor }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                    tile("Workers", status.map { "\($0.processes.filter { $0.state.uppercased() == "RUNNING" }.count) / \($0.processes.count)" } ?? "—",
                         "running under Supervisor")
                    tile("Waiting jobs", queue?.pending.map(String.init) ?? "—", "in the queue now")
                    tile("Failed jobs", queue?.failed.map(String.init) ?? (hasLoaded ? "\(failed.count)" : "—"), "in failed_jobs",
                         tint: (queue?.failed ?? failed.count) > 0 ? .statusDangerText : nil)
                    tile("Scheduler", scheduler.map { $0.active ? "On" : "Off" } ?? "—", "schedule:run every minute",
                         tint: scheduler?.active == false ? .statusWarningText : nil)
                }
                workersCard
                failedCard
                schedulerCard
            }
            .padding(24)
        }
        .task(id: siteID) { await load() }
    }

    private func load() async {
        let api = environment.api
        async let supervisor = try? api.supervisorStatus(siteID: siteID)
        async let stats = try? api.queueStats(siteID: siteID)
        async let jobs = try? api.failedJobs(siteID: siteID)
        async let schedule = try? api.scheduler(siteID: siteID)
        status = await supervisor
        queue = await stats
        failed = await jobs ?? []
        scheduler = await schedule
        hasLoaded = true
    }

    private func reloadSoon() {
        Task {
            try? await Task.sleep(for: .seconds(2))
            await load()
        }
    }

    private func tile(_ caption: String, _ value: String, _ detail: String, tint: Color? = nil) -> some View {
        let icons: [String: (String, Color)] = [
            "Workers": ("gearshape.2.fill", Vivid.teal), "Waiting jobs": ("tray.full.fill", Vivid.blue),
            "Failed jobs": ("xmark.octagon.fill", Vivid.pink), "Scheduler": ("calendar.badge.clock", Vivid.purple)
        ]
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(caption).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                if let icon = icons[caption] { IconBadge(symbol: icon.0, tint: icon.1) }
            }
            Text(value).font(.system(size: 22, weight: .semibold)).monospacedDigit().foregroundStyle(tint ?? .primary)
            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .card()
        .accessibilityElement(children: .combine)
    }

    // MARK: - Workers

    private var workersCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionHeader(title: "Worker processes", symbol: "gearshape.2.fill", tint: Vivid.teal)
                Spacer()
                ForEach([OrchestratorAPI.SupervisorAction.start, .restart, .stop], id: \.self) { action in
                    Button("\(action.title) All…") { control(action) }
                        .disabled(isWorking || status == nil)
                        .help(action == .stop ? "Asks for confirmation and Touch ID" : "Asks for confirmation")
                }
            }
            .controlSize(.small)
            if let status, !status.processes.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(status.processes.enumerated()), id: \.element.id) { index, process in
                        if index > 0 { Divider() }
                        HStack(spacing: 10) {
                            Circle().fill(process.tone.color).frame(width: 8, height: 8)
                                .accessibilityHidden(true)
                            Text(process.name).font(.system(size: 12, design: .monospaced)).lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(process.description ?? "").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                            Text(process.state.capitalized).font(.system(size: 12)).foregroundStyle(.secondary)
                                .frame(width: 80, alignment: .trailing)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .accessibilityElement(children: .combine)
                    }
                }
                .card()
            } else {
                LoadingOrEmptyRow(isLoading: !hasLoaded, text: "No Supervisor workers for this site", symbol: "gearshape.2")
            }
        }
    }

    private func control(_ action: OrchestratorAPI.SupervisorAction) {
        isWorking = true
        Task {
            defer { isWorking = false }
            if await executor.controlWorkers(siteID: siteID, action: action) { reloadSoon() }
        }
    }

    // MARK: - Failed jobs

    private var failedCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionHeader(title: "Failed jobs", symbol: "xmark.octagon.fill", tint: Vivid.pink)
                Spacer()
                Button("Retry All…") {
                    let count = failed.count
                    Task { if await executor.retryAllFailedJobs(siteID: siteID, count: count) { reloadSoon() } }
                }
                .controlSize(.small)
                .disabled(failed.isEmpty)
            }
            if failed.isEmpty {
                LoadingOrEmptyRow(isLoading: !hasLoaded, text: "No failed jobs", symbol: "checkmark.circle")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(failed.prefix(50).enumerated()), id: \.element.id) { index, job in
                        if index > 0 { Divider() }
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(job.jobName ?? "Job").font(.system(size: 12, weight: .semibold, design: .monospaced))
                                if let exception = job.exception {
                                    Text(exception.components(separatedBy: "\n").first ?? exception)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(Color.statusDangerText)
                                        .lineLimit(2)
                                        .textSelection(.enabled)
                                }
                                Text([job.queue, job.failedAt.map { RelativeTime.ago($0) }].compactMap { $0 }.joined(separator: " · "))
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Button("Retry…") {
                                Task { if await executor.retryFailedJob(siteID: siteID, job: job) { reloadSoon() } }
                            }
                            .buttonStyle(RowButtonStyle())
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                }
                .card()
            }
        }
    }

    // MARK: - Scheduler

    private var schedulerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Scheduler", symbol: "calendar.badge.clock", tint: Vivid.purple)
            VStack(alignment: .leading, spacing: 6) {
                if let scheduler {
                    Text(scheduler.active ? "The cron entry runs schedule:run every minute." : "No cron entry: scheduled tasks do not run.")
                        .font(.system(size: 12))
                    if !scheduler.currentContent.isEmpty {
                        Text(scheduler.currentContent.trimmingCharacters(in: .whitespacesAndNewlines))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                } else {
                    if hasLoaded {
                        Text("Could not read the scheduler.").foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 6) { SkeletonBar(height: 9); SkeletonBar(width: 260, height: 8) }.shimmering()
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }
}
