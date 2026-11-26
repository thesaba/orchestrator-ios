import Charts
import OrchestratorKit
import SwiftUI

/// Monitored sites, worst first: response-time sparkline, 24 h uptime and p95.
struct UptimeCard: View {
    let model: MainWindowModel
    var rows: [DashboardSummary.UptimeRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Uptime & response · 24 h")
            if rows.isEmpty {
                EmptyRow(text: "No monitored sites", symbol: "waveform.path.ecg")
            } else {
                VStack(spacing: 0) {
                    header
                    ForEach(rows) { row in
                        Divider()
                        UptimeRowView(row: row, sparkline: model.data.sparklines[row.siteID] ?? [])
                            .contentShape(Rectangle())
                            .onTapGesture { model.openSite(row.siteID) }
                    }
                }
                .card()
                .onAppear { model.data.requestSparklines(for: rows.map(\.siteID)) }
                .onChange(of: rows.map(\.siteID)) { _, ids in model.data.requestSparklines(for: ids) }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Site").frame(maxWidth: .infinity, alignment: .leading)
            Text("Response time").frame(width: 120, alignment: .leading)
            Text("Uptime").frame(width: 60, alignment: .trailing)
            Text("p95").frame(width: 64, alignment: .trailing)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .accessibilityHidden(true)
    }
}

private struct UptimeRowView: View {
    var row: DashboardSummary.UptimeRow
    var sparkline: [Double]

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                StatusMarkView(mark: row.mark, size: 12)
                Text(row.domain).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Sparkline(values: sparkline)
                .frame(width: 120, height: 20)
            Text(row.uptimePercent.map { "\($0)%" } ?? "—")
                .foregroundStyle(row.mark == .warning || row.mark == .failure ? row.mark.textTint : .primary)
                .frame(width: 60, alignment: .trailing)
            Text(row.p95.map { "\($0) ms" } ?? "—")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12)
        .frame(height: 32)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.domain)
        .accessibilityValue("\(row.mark.accessibilityLabel), uptime \(row.uptimePercent.map { "\($0) percent" } ?? "unknown"), p95 \(row.p95.map { "\($0) milliseconds" } ?? "unknown")")
    }
}

/// A small teal line, scaled to its own range. Empty while loading.
struct Sparkline: View {
    var values: [Double]

    var body: some View {
        if values.count > 1 {
            Chart(Array(values.enumerated()), id: \.offset) { item in
                LineMark(x: .value("Sample", item.offset), y: .value("ms", item.element))
                    .foregroundStyle(Color.brandTeal)
                    .lineStyle(StrokeStyle(lineWidth: 1.2))
                    .interpolationMethod(.monotone)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: 0...(max(values.max() ?? 1, 1) * 1.15))
            .accessibilityHidden(true)
        } else {
            Color.clear
        }
    }
}
