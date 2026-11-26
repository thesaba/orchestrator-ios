import Charts
import OrchestratorKit
import SwiftUI

/// Fleet-average CPU, RAM and disk over the chosen range.
struct ResourcesCard: View {
    @Bindable var data: MainDataStore
    var overview: FleetOverview
    @State private var expanded = false

    var body: some View {
        let points = data.resources[data.range] ?? []
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionHeader(title: "Resources · fleet average", symbol: "chart.xyaxis.line", tint: Vivid.indigo)
                Picker("Range", selection: $data.range) {
                    ForEach(MetricsRange.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .controlSize(.small)
                ExpandChartButton { expanded = true }
            }
            if points.isEmpty {
                if data.isLoadingResources || data.resources[data.range] == nil && !overview.servers.isEmpty {
                    HStack(spacing: 10) { SkeletonChart(); SkeletonChart(); SkeletonChart() }
                } else {
                    Text(overview.servers.isEmpty ? "Fleet metrics need an admin account." : "No samples in this range yet.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 110)
                        .card()
                }
            } else {
                HStack(spacing: 10) {
                    MetricChart(title: "CPU", symbol: "cpu", points: points, metric: \.cpu, color: .chartCPU,
                                detail: peakText(points, \.cpu))
                    MetricChart(title: "RAM", symbol: "memorychip", points: points, metric: \.ram, color: .brandTeal,
                                detail: changeText(points, \.ram))
                    MetricChart(title: "Disk", symbol: "internaldrive", points: points, metric: \.disk, color: Vivid.orange,
                                detail: fullestDisk ?? changeText(points, \.disk))
                }
            }
        }
        .sheet(isPresented: $expanded) { FleetResourcesSheet(data: data) }
    }

    private func peakText(_ points: [ResourcePoint], _ metric: KeyPath<ResourcePoint, Double>) -> String {
        guard let peak = ResourceAverager.peak(points, metric) else { return " " }
        let when = data.range.duration > 86_400
            ? peak.date.formatted(.dateTime.day().month(.abbreviated))
            : peak.date.formatted(date: .omitted, time: .shortened)
        return "peak \(Int(peak.value.rounded()))% at \(when)"
    }

    private func changeText(_ points: [ResourcePoint], _ metric: KeyPath<ResourcePoint, Double>) -> String {
        guard let change = ResourceAverager.change(points, metric) else { return " " }
        let rounded = Int(change.rounded())
        if rounded == 0 { return "steady over \(data.range.rawValue)" }
        return "\(rounded > 0 ? "rising" : "falling") \(abs(rounded))% in \(data.range.rawValue)"
    }

    /// "do-fra-db-01 at 91%" when one disk is above 80%.
    private var fullestDisk: String? {
        guard let server = overview.servers.max(by: { ($0.server.diskPercent ?? 0) < ($1.server.diskPercent ?? 0) }),
              let percent = server.server.diskPercent, percent >= 80 else { return nil }
        return "\(server.server.name) at \(Int(percent.rounded()))%"
    }
}

private struct MetricChart: View {
    var title: String
    var symbol: String
    var points: [ResourcePoint]
    var metric: KeyPath<ResourcePoint, Double>
    var color: Color
    var detail: String

    var body: some View {
        let now: Double = points.last.map { $0[keyPath: metric] } ?? 0
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: symbol).foregroundStyle(color).accessibilityHidden(true)
                Text(title)
                Spacer()
                Text("\(Int(now.rounded()))%")
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy, value: Int(now.rounded()))
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            InteractiveLineChart(
                series: [ChartSeries(name: title, color: color,
                                     points: points.map { SeriesPoint(date: $0.date, value: $0[keyPath: metric]) })],
                unit: .percent, yDomain: 0...100, style: .card)
                .frame(height: 64)

            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title), fleet average")
    }
}
