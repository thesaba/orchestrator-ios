import OrchestratorKit
import SwiftUI

// The large views behind each chart's expand button. They read the same data as the cards,
// add range and series controls, and show statistics under the chart. All loading is GET.

/// Fleet-average CPU, RAM and disk, from the Dashboard.
struct FleetResourcesSheet: View {
    @Bindable var data: MainDataStore
    @State private var hidden: Set<String> = []

    private var series: [ChartSeries] {
        let points = data.resources[data.range] ?? []
        return [
            ChartSeries(name: "CPU", color: Vivid.indigo, points: points.map { SeriesPoint(date: $0.date, value: $0.cpu) }),
            ChartSeries(name: "RAM", color: Vivid.teal, points: points.map { SeriesPoint(date: $0.date, value: $0.ram) }),
            ChartSeries(name: "Disk", color: Vivid.orange, points: points.map { SeriesPoint(date: $0.date, value: $0.disk) })
        ]
    }

    var body: some View {
        let shown = series.filter { !hidden.contains($0.name) }
        ExpandedChartSheet(title: "Fleet resources", subtitle: "Average of every server, \(data.range.rawValue)") {
            SeriesToggles(names: series.map { ($0.name, $0.color) }, hidden: $hidden)
            RangePicker(range: $data.range)
        } chart: {
            if data.resources[data.range] == nil {
                SkeletonChart(height: 340)
            } else {
                InteractiveLineChart(series: shown, unit: .percent, yDomain: 0...100, style: .expanded)
            }
        } footer: {
            SeriesStatsGrid(series: shown, unit: .percent)
        }
    }
}

/// One server's CPU, RAM and disk over a chosen range.
struct ServerMetricsSheet: View {
    let api: OrchestratorAPI
    let serverID: Int
    let serverName: String
    @State var range: MetricsRange
    @State private var points: [FleetMetricsHistory.Point]?
    @State private var hidden: Set<String> = []

    private var series: [ChartSeries] {
        let points = self.points ?? []
        return [
            ChartSeries(name: "CPU", color: Vivid.indigo, points: points.map { SeriesPoint(date: $0.t, value: $0.cpu) }),
            ChartSeries(name: "RAM", color: Vivid.teal, points: points.map { SeriesPoint(date: $0.t, value: $0.ram) }),
            ChartSeries(name: "Disk", color: Vivid.orange, points: points.map { SeriesPoint(date: $0.t, value: $0.disk) })
        ]
    }

    var body: some View {
        let shown = series.filter { !hidden.contains($0.name) }
        ExpandedChartSheet(title: serverName, subtitle: "CPU, RAM and disk · \(range.rawValue)") {
            SeriesToggles(names: series.map { ($0.name, $0.color) }, hidden: $hidden)
            RangePicker(range: $range)
        } chart: {
            if points == nil {
                SkeletonChart(height: 340)
            } else {
                InteractiveLineChart(series: shown, unit: .percent, yDomain: 0...100, style: .expanded)
            }
        } footer: {
            SeriesStatsGrid(series: shown, unit: .percent)
        }
        .task(id: range) {
            points = nil
            points = (try? await api.fleetMetrics(serverID: serverID, range: range).points) ?? []
        }
    }
}

/// Response times of several sites over 24 hours, from the Dashboard's uptime card.
struct ResponseTimesSheet: View {
    let data: MainDataStore
    let sites: [(id: Int, domain: String)]
    @State private var hidden: Set<String> = []

    private static let palette: [Color] = [Vivid.pink, Vivid.blue, Vivid.teal, Vivid.orange, Vivid.purple, Vivid.green, Vivid.yellow, Vivid.indigo]

    private var series: [ChartSeries] {
        sites.enumerated().map { index, site in
            ChartSeries(name: site.domain, color: Self.palette[index % Self.palette.count], points: data.sparklines[site.id] ?? [])
        }
    }

    var body: some View {
        let shown = series.filter { !hidden.contains($0.name) }
        ExpandedChartSheet(title: "Response times", subtitle: "The most recent uptime checks") {
            SeriesToggles(names: series.map { ($0.name, $0.color) }, hidden: $hidden)
        } chart: {
            InteractiveLineChart(series: shown, unit: .milliseconds, style: .expanded)
        } footer: {
            SeriesStatsGrid(series: shown, unit: .milliseconds)
        }
        .onAppear { data.requestSparklines(for: sites.map(\.id)) }
    }
}

/// One site's response time, from the site page or the inspector.
struct SiteResponseSheet: View {
    let data: MainDataStore
    let siteID: Int
    let domain: String

    var body: some View {
        let series = [ChartSeries(name: "Response time", color: Vivid.pink, points: data.sparklines[siteID] ?? [])]
        ExpandedChartSheet(title: domain, subtitle: "Response time of the most recent uptime checks") {
            EmptyView()
        } chart: {
            if series[0].points.isEmpty {
                SkeletonChart(height: 340)
            } else {
                InteractiveLineChart(series: series, unit: .milliseconds, style: .expanded)
            }
        } footer: {
            SeriesStatsGrid(series: series, unit: .milliseconds)
        }
        .onAppear { data.requestSparklines(for: [siteID]) }
    }
}

/// Invoiced and collected per month, from Billing.
struct BillingChartSheet: View {
    let invoices: [Invoice]
    let currency: String
    @State private var months = 12
    @State private var hidden: Set<String> = []

    var body: some View {
        let data = BillingMonth.last(months, of: invoices, currency: currency)
        ExpandedChartSheet(title: "Invoiced and collected", subtitle: "\(currency), by month") {
            SeriesToggles(names: [("Invoiced", Vivid.indigo), ("Collected", Vivid.green)], hidden: $hidden)
            Picker("Months", selection: $months) {
                Text("6 months").tag(6)
                Text("12 months").tag(12)
                Text("24 months").tag(24)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        } chart: {
            MonthBarsChart(months: data, currency: currency,
                           showInvoiced: !hidden.contains("Invoiced"), showCollected: !hidden.contains("Collected"),
                           expanded: true)
        } footer: {
            let invoiced = data.reduce(0) { $0 + $1.invoiced }
            let collected = data.reduce(0) { $0 + $1.collected }
            HStack(spacing: 28) {
                stat("Invoiced", Money.string(invoiced, currency: currency), Vivid.indigo)
                stat("Collected", Money.string(collected, currency: currency), Vivid.green)
                stat("Collected share", invoiced > 0 ? "\(Int((Double(collected) / Double(invoiced) * 100).rounded()))%" : "—", Vivid.teal)
                stat("Best month", data.max { $0.collected < $1.collected }.map { $0.month.formatted(.dateTime.month(.wide).year()) } ?? "—", Vivid.orange)
                Spacer()
            }
            .padding(14)
            .card()
        }
    }

    private func stat(_ caption: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(caption).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Text(value).font(.system(size: 15, weight: .semibold)).monospacedDigit()
        }
    }
}

/// 1h · 6h · 24h · 7d · 30d.
struct RangePicker: View {
    @Binding var range: MetricsRange

    var body: some View {
        Picker("Range", selection: $range) {
            ForEach(MetricsRange.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }
}
