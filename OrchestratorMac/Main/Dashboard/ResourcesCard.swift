import Charts
import OrchestratorKit
import SwiftUI

/// Fleet-average CPU, RAM and disk over the chosen range.
struct ResourcesCard: View {
    @Bindable var data: MainDataStore
    var overview: FleetOverview

    var body: some View {
        let points = data.resources[data.range] ?? []
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionHeader(title: "Resources · fleet average")
                Picker("Range", selection: $data.range) {
                    ForEach(MetricsRange.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .controlSize(.small)
            }
            if points.isEmpty {
                Group {
                    if data.isLoadingResources || data.resources[data.range] == nil && !overview.servers.isEmpty {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(overview.servers.isEmpty ? "Fleet metrics need an admin account." : "No samples in this range yet.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 110)
                .card()
            } else {
                HStack(spacing: 10) {
                    MetricChart(title: "CPU", points: points, metric: \.cpu, color: .chartCPU,
                                detail: peakText(points, \.cpu))
                    MetricChart(title: "RAM", points: points, metric: \.ram, color: .brandTeal,
                                detail: changeText(points, \.ram))
                    MetricChart(title: "Disk", points: points, metric: \.disk, color: .statusWarning,
                                detail: fullestDisk ?? changeText(points, \.disk))
                }
            }
        }
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
    var points: [ResourcePoint]
    var metric: KeyPath<ResourcePoint, Double>
    var color: Color
    var detail: String

    var body: some View {
        let now: Double = points.last.map { $0[keyPath: metric] } ?? 0
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(now.rounded()))%")
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            Chart(points) { point in
                AreaMark(x: .value("Time", point.date), y: .value(title, point[keyPath: metric]))
                    .foregroundStyle(color.opacity(0.2))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Time", point.date), y: .value(title, point[keyPath: metric]))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .interpolationMethod(.monotone)
            }
            .chartYScale(domain: 0...100)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(values: [0, 50, 100]) { _ in AxisGridLine().foregroundStyle(.quaternary) }
            }
            .frame(height: 64)

            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), fleet average")
        .accessibilityValue("\(Int(now.rounded())) percent now, \(detail)")
    }
}
