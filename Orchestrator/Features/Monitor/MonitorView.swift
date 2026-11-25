import SwiftUI
import Charts
import OrchestratorKit

struct MonitorView: View {
    @State private var model = MonitorViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if let error = model.fatalError, model.system == nil {
                    ErrorStateView(error: error) { Task { await model.load() } }
                } else if !model.hasLoadedOnce {
                    LoadingStateView(title: "Reading server metrics…")
                } else {
                    content
                }
            }
            .navigationTitle("Monitor")
            .refreshable { await model.load() }
            .task { if !model.hasLoadedOnce { await model.load() } }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 14) {
                if !model.degradedSections.isEmpty {
                    InlineErrorBanner(message: "Could not load: \(model.degradedSections.joined(separator: ", ")).")
                }

                nowCard
                historyCard
                servicesCard
                processesCard
                performanceCard
                deployStatsCard
                systemInfoCard
                links
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var nowCard: some View {
        SectionCard("Right now", systemImage: "gauge.with.dots.needle.67percent") {
            if let system = model.system {
                VStack(alignment: .leading, spacing: 14) {
                    UsageBar(
                        label: "CPU",
                        percent: system.cpu.percent,
                        detail: "load \(String(format: "%.2f", system.cpu.load1 ?? 0)) · \(String(format: "%.2f", system.cpu.load5 ?? 0)) · \(String(format: "%.2f", system.cpu.load15 ?? 0))"
                    )
                    UsageBar(
                        label: "Memory",
                        percent: system.ram.percent,
                        detail: "\(Bytes.string(system.ram.used)) of \(Bytes.string(system.ram.total))"
                    )
                    UsageBar(
                        label: "Disk",
                        percent: system.disk.percent,
                        detail: "\(Bytes.string(system.disk.used)) of \(Bytes.string(system.disk.total))"
                    )
                    if let swap = system.swap, (swap.total ?? 0) > 0 {
                        UsageBar(
                            label: "Swap",
                            percent: swap.percent,
                            detail: "\(Bytes.string(swap.used)) of \(Bytes.string(swap.total))"
                        )
                    }
                }
            }
        }
    }

    private var historyCard: some View {
        SectionCard(
            "Last \(model.history?.hours ?? 24) hours",
            systemImage: "chart.xyaxis.line"
        ) {
            if model.chartSamples.isEmpty {
                Text("No samples recorded.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(model.chartSamples) { sample in
                        LineMark(
                            x: .value("Time", sample.checkedAt),
                            y: .value("Percent", sample.cpuPercent ?? 0),
                            series: .value("Metric", "CPU")
                        )
                        .foregroundStyle(by: .value("Metric", "CPU"))

                        LineMark(
                            x: .value("Time", sample.checkedAt),
                            y: .value("Percent", sample.ramPercent ?? 0),
                            series: .value("Metric", "RAM")
                        )
                        .foregroundStyle(by: .value("Metric", "RAM"))

                        LineMark(
                            x: .value("Time", sample.checkedAt),
                            y: .value("Percent", sample.diskPercent ?? 0),
                            series: .value("Metric", "Disk")
                        )
                        .foregroundStyle(by: .value("Metric", "Disk"))
                    }
                }
                .chartYScale(domain: 0...100)
                .chartYAxisLabel("%")
                .chartLegend(position: .bottom)
                .frame(height: 190)
            }
        }
    }

    private var servicesCard: some View {
        SectionCard("Services", systemImage: "square.stack.3d.up") {
            if model.services.isEmpty {
                Text("No services reported.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(model.services) { service in
                        HStack {
                            StatusDot(tone: service.tone)
                            Text(service.name)
                                .font(.callout)
                            Spacer()
                            Text(service.status)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(service.tone.color)
                        }
                    }
                }
            }
        }
    }

    private var processesCard: some View {
        SectionCard("Top processes", systemImage: "cpu") {
            if model.topProcesses.isEmpty {
                Text("No process data.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(model.topProcesses) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.name)
                                    .font(.callout)
                                if let count = entry.count, count > 1 {
                                    Text("\(count) processes")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(String(format: "%.1f%% CPU", entry.cpuPercent ?? 0))
                                    .font(.caption.monospacedDigit())
                                Text(Bytes.string(entry.rssBytes))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var performanceCard: some View {
        SectionCard("Response times (p95)", systemImage: "speedometer") {
            if model.slowestSites.isEmpty {
                Text("No performance samples.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Chart(model.slowestSites) { entry in
                    BarMark(
                        x: .value("p95", entry.p95 ?? 0),
                        y: .value("Site", entry.domain)
                    )
                    .foregroundStyle(entry.tone.color)
                    .annotation(position: .trailing) {
                        Text("\(entry.p95 ?? 0)ms")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .chartXAxisLabel("ms")
                .frame(height: CGFloat(model.slowestSites.count) * 28 + 30)
            }
        }
    }

    private var deployStatsCard: some View {
        SectionCard("Deploys per day", systemImage: "arrow.up.circle") {
            let days = model.deployStats?.days ?? []
            if days.isEmpty {
                Text("No deploys in this period.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(days) { day in
                        BarMark(
                            x: .value("Day", day.date, unit: .day),
                            y: .value("Count", day.success)
                        )
                        .foregroundStyle(Color.green)

                        BarMark(
                            x: .value("Day", day.date, unit: .day),
                            y: .value("Count", day.failed)
                        )
                        .foregroundStyle(Color.red)
                    }
                }
                .frame(height: 140)
            }
        }
    }

    private var systemInfoCard: some View {
        SectionCard("System", systemImage: "info.circle") {
            if let info = model.info {
                VStack(alignment: .leading, spacing: 8) {
                    DetailRow(label: "OS", value: info.os)
                    DetailRow(label: "Kernel", value: info.kernel, monospaced: true)
                    DetailRow(label: "Uptime", value: Durations.uptime(info.uptimeSeconds))
                    HStack {
                        Text("Firewall").foregroundStyle(.secondary)
                        Spacer()
                        StatusBadge(status: info.ufwStatus)
                    }
                    .font(.callout)
                    HStack {
                        Text("Pending updates").foregroundStyle(.secondary)
                        Spacer()
                        Text("\(info.pendingUpdates ?? 0)")
                            .foregroundStyle((info.pendingUpdates ?? 0) > 0 ? Color.orange : Color.primary)
                    }
                    .font(.callout)
                    if info.rebootRequired {
                        Label("Reboot required", systemImage: "arrow.triangle.2.circlepath")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    private var links: some View {
        VStack(spacing: 0) {
            NavigationLink { UptimeView() } label: {
                linkRow("Uptime monitors", systemImage: "waveform.path.ecg")
            }
            Divider().padding(.leading, 46)
            NavigationLink { CertificatesView() } label: {
                linkRow("Certificates", systemImage: "lock.shield")
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func linkRow(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .frame(width: 22)
                .foregroundStyle(.tint)
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
    }
}
