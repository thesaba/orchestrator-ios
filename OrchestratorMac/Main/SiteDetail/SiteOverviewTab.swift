import Charts
import OrchestratorKit
import SwiftUI

/// The site at a glance: state tiles, the newest deploy, facts, response time, recent errors
/// and the everyday actions.
struct SiteOverviewTab: View {
    let environment: AppEnvironment
    let model: MainWindowModel
    var row: SiteTableRow

    @State private var errors: [LogError] = []
    @State private var responseExpanded = false
    @State private var errorsLoaded = false

    private var executor: CommandExecutor { environment.executor }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                    tile("Uptime · 24 h", symbol: "waveform.path.ecg", color: Vivid.pink, row.uptimePercent.map { "\($0)%" } ?? "—",
                         row.uptimePercent == nil ? "Not monitored" : "from the uptime check",
                         tint: (row.uptimePercent ?? 100) < 99 ? .statusWarningText : nil)
                    tile("Response p95", symbol: "speedometer", color: Vivid.blue, row.p95.map { "\($0) ms" } ?? "—", "last 24 h")
                    tile("Certificate", symbol: "lock.shield.fill", color: Vivid.green, row.sslEnabled ? (row.sslDaysLeft.map { "\($0) days" } ?? "On") : "Off",
                         row.sslEnabled ? "left before it expires" : "HTTPS is off",
                         tint: row.sslEnabled && (row.sslDaysLeft ?? .max) <= AppSettings.sslWarningDays ? .statusWarningText : nil)
                    tile("Last deploy", symbol: "arrow.up.circle.fill", color: Vivid.indigo, row.lastDeployAt.map { RelativeTime.ago($0) } ?? "Never",
                         row.isDeploying ? "running now" : (row.lastDeployStatus ?? ""),
                         tint: row.lastDeployFailed ? .statusDangerText : nil)
                }

                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 16) {
                        deployCard
                        responseCard
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    VStack(alignment: .leading, spacing: 16) {
                        actionsCard
                        errorsCard
                    }
                    .frame(width: 340, alignment: .topLeading)
                }
            }
            .padding(24)
        }
        .sheet(isPresented: $responseExpanded) {
            SiteResponseSheet(data: model.data, siteID: row.id, domain: row.domain)
        }
        .task(id: row.id) {
            model.data.requestSparklines(for: [row.id])
            errors = (try? await environment.api.logErrors(siteID: row.id).errors.filter { !$0.resolved }) ?? []
            errorsLoaded = true
        }
    }

    private func tile(_ caption: String, symbol: String, color: Color, _ value: String, _ detail: String, tint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(caption).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                IconBadge(symbol: symbol, tint: color)
            }
            Text(value)
                .font(.system(size: 22, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(tint ?? .primary)
            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .card()
        .accessibilityElement(children: .combine)
    }

    // MARK: - Deploy

    private var deployCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: row.isDeploying ? "Deploying now" : "Newest deploy", symbol: "arrow.up.circle.fill", tint: Vivid.blue,
                          trailing: "All deploys") { model.siteTab = .deploys }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    StatusMarkView(mark: row.isDeploying ? .deploying : (row.lastDeployFailed ? .failure : .healthy), size: 14)
                    Text([row.branch, row.shortCommit].compactMap { $0 }.joined(separator: " · ").ifEmpty("No deploys yet"))
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                    Spacer()
                    if let duration = row.deploy?.durationSeconds, !row.isDeploying {
                        Text(DurationText.short(duration)).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                if let message = row.deploy?.commitMessage {
                    Text(message).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                }
                if row.isDeploying {
                    if let step = row.deploy?.currentStep {
                        Text("Step \(step.number) of \(row.deploy?.totalSteps ?? step.total) · \(step.title)")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.accentText)
                    }
                    if let progress = row.deploy?.progress { ProgressBar(fraction: progress, tint: .brandTeal) }
                    Button("Show the live log") { model.siteTab = .deploys }
                        .buttonStyle(.link)
                        .font(.system(size: 12, weight: .medium))
                } else if row.lastDeployFailed, let step = row.deploy?.failedStep {
                    Text("Failed at step \(step.number): \(step.title)")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.statusDangerText)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(tint: row.isDeploying ? .tintInfo : (row.lastDeployFailed ? .tintDanger : nil))
        }
    }

    // MARK: - Response time

    private var responseCard: some View {
        let values = model.data.sparklines[row.id] ?? []
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionHeader(title: "Response time · recent checks", symbol: "waveform.path.ecg", tint: Vivid.pink)
                if values.count > 1 { ExpandChartButton { responseExpanded = true } }
            }
            Group {
                if values.count > 1 {
                    InteractiveLineChart(series: [ChartSeries(name: "Response time", color: Vivid.pink, points: values)],
                                         unit: .milliseconds, style: .card)
                        .frame(height: 140)
                    .accessibilityLabel("Response time over 24 hours")
                } else if row.uptimePercent == nil {
                    Text("This site is not monitored.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 140)
                } else {
                    WavePlaceholder().frame(height: 140)
                }
            }
            .padding(12)
            .card()
        }
    }

    // MARK: - Actions

    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Actions", symbol: "bolt.fill", tint: Vivid.yellow)
            VStack(spacing: 0) {
                action("Clear Cache…", "trash", "Runs optimize:clear") {
                    let id = row.id
                    Task { await executor.runArtisan(siteID: id, command: "optimize:clear") }
                }
                Divider()
                action("Restart Queue…", "arrow.clockwise", "Runs queue:restart") {
                    let id = row.id
                    Task { await executor.runArtisan(siteID: id, command: "queue:restart") }
                }
                Divider()
                action("Deploy Branch, Tag or Commit…", "arrow.triangle.branch", nil) {
                    let id = row.id
                    Task { await executor.deployChoosingRef(siteID: id) }
                }
                Divider()
                action("Roll Back…", "arrow.uturn.backward", "Touch ID") {
                    let id = row.id
                    Task { await executor.rollback(siteID: id) }
                }
                if row.sslEnabled {
                    Divider()
                    action("Renew Certificate…", "lock.rotation", nil) {
                        let id = row.id
                        Task { await executor.renewCertificate(siteID: id) }
                    }
                }
            }
            .card()
        }
    }

    private func action(_ title: String, _ symbol: String, _ note: String?, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 10) {
                Image(systemName: symbol).frame(width: 16).foregroundStyle(Color.accentText)
                Text(title)
                Spacer()
                if let note { Text(note).font(.system(size: 11)).foregroundStyle(.secondary) }
            }
            .font(.system(size: 13))
            .padding(.horizontal, 12)
            .frame(height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Errors

    private var errorsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Unresolved errors", symbol: "ladybug.fill", tint: Vivid.pink, trailing: "Logs") { model.siteTab = .logs }
            if !errorsLoaded {
                SkeletonRows(count: 3)
            } else if errors.isEmpty {
                EmptyRow(text: "No unresolved errors", symbol: "checkmark.circle")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(errors.prefix(5).enumerated()), id: \.element.id) { index, error in
                        if index > 0 { Divider() }
                        LogErrorRow(error: error)
                    }
                }
                .card()
            }
        }
    }
}

/// One grouped Laravel error: class, message, count and when it was last seen.
struct LogErrorRow: View {
    var error: LogError

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(error.headline)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                if let message = error.message {
                    Text(message).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                }
                if let last = error.lastSeenAt {
                    Text("last \(RelativeTime.ago(last))").font(.system(size: 11)).foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let count = error.count {
                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.statusDangerText)
                    .padding(.horizontal, 7)
                    .frame(minWidth: 26, minHeight: 20)
                    .background(Capsule().fill(Color.tintDanger))
                    .accessibilityLabel("\(count) times")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

extension String {
    func ifEmpty(_ replacement: String) -> String { isEmpty ? replacement : self }
}

/// A shimmering wave while a chart's data loads.
struct WavePlaceholder: View {
    var body: some View {
        SkeletonChart(height: 140)
    }
}
