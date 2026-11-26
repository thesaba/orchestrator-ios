import Charts
import OrchestratorKit
import SwiftUI

// Every chart in the main window is built from these: hovering shows the value under the
// pointer (a rule, a dot per series and a small readout), and each card can open the chart
// large with more controls.

/// How a chart's values read.
enum ChartUnit: Hashable {
    case percent
    case milliseconds
    /// Minor units of a currency.
    case money(String)

    func format(_ value: Double) -> String {
        switch self {
        case .percent:            return "\(Int(value.rounded()))%"
        case .milliseconds:       return "\(Int(value.rounded())) ms"
        case .money(let code):    return Money.string(Int(value.rounded()), currency: code)
        }
    }
}

/// One named, coloured line.
struct ChartSeries: Identifiable, Hashable {
    var name: String
    var color: Color
    var points: [SeriesPoint]

    var id: String { name }
}

/// A time series chart with a hover readout.
///
/// - `compact`: no axes, a one-line readout (sparklines in rows).
/// - `card`: light grid, the readout above the pointer (cards on screens).
/// - `expanded`: both axes with labels (the large view in a sheet).
struct InteractiveLineChart: View {
    enum Style { case compact, card, expanded }

    var series: [ChartSeries]
    var unit: ChartUnit
    var yDomain: ClosedRange<Double>?
    var threshold: Double?
    var style: Style = .card
    /// Draw in from the left on first appearance.
    var reveal = true

    @State private var hoverDate: Date?

    private var visible: [ChartSeries] { series.filter { !$0.points.isEmpty } }

    private var domain: ClosedRange<Double> {
        if let yDomain { return yDomain }
        let top = visible.flatMap(\.points).map(\.value).max() ?? 1
        return 0...max(top * 1.15, 1)
    }

    var body: some View {
        chart
            .chartYScale(domain: domain)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) {
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel()
                }
            }
            .chartXAxis(style == .expanded ? .automatic : .hidden)
            .chartYAxis {
                if style == .expanded {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                        AxisGridLine().foregroundStyle(.quaternary)
                        AxisValueLabel { if let number = value.as(Double.self) { Text(unit.format(number)) } }
                    }
                } else {
                    AxisMarks(values: .automatic(desiredCount: 3)) { _ in AxisGridLine().foregroundStyle(.quaternary) }
                }
            }
            .chartYAxis(style == .compact ? .hidden : .automatic)
            .chartLegend(.hidden)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                guard let plot = proxy.plotFrame else { return }
                                let x = location.x - geometry[plot].origin.x
                                guard let date: Date = proxy.value(atX: x),
                                      let anchor = visible.first.flatMap({ SeriesStats.nearest(to: date, in: $0.points) }) else { return }
                                hoverDate = anchor.date
                            case .ended:
                                hoverDate = nil
                            }
                        }
                }
            }
            .animation(.easeInOut(duration: 0.5), value: series)
            .modifier(OptionalReveal(enabled: reveal))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(visible.map(\.name).joined(separator: ", "))
            .accessibilityValue(accessibilitySummary)
    }

    private var chart: some View {
        Chart {
            ForEach(visible) { line in
                ForEach(line.points) { point in
                    if visible.count == 1 {
                        AreaMark(x: .value("Time", point.date), y: .value(line.name, point.value))
                            .foregroundStyle(LinearGradient(colors: [line.color.opacity(0.32), line.color.opacity(0.02)],
                                                            startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                    }
                    LineMark(x: .value("Time", point.date), y: .value(line.name, point.value),
                             series: .value("Series", line.name))
                        .foregroundStyle(line.color)
                        .lineStyle(StrokeStyle(lineWidth: style == .compact ? 1.2 : (style == .expanded ? 2 : 1.6)))
                        .interpolationMethod(.monotone)
                }
            }
            if let threshold {
                RuleMark(y: .value("Limit", threshold))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            if let hoverDate {
                RuleMark(x: .value("Pointer", hoverDate))
                    .foregroundStyle(.secondary.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: style == .compact ? .trailing : .top, spacing: 4,
                                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        readout(at: hoverDate)
                    }
                ForEach(visible) { line in
                    if let point = SeriesStats.nearest(to: hoverDate, in: line.points) {
                        PointMark(x: .value("Time", point.date), y: .value(line.name, point.value))
                            .foregroundStyle(line.color)
                            .symbolSize(style == .compact ? 22 : 46)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func readout(at date: Date) -> some View {
        if style == .compact {
            let value = visible.first.flatMap { SeriesStats.nearest(to: date, in: $0.points) }?.value
            Text("\(value.map(unit.format) ?? "—") · \(date.formatted(date: .omitted, time: .shortened))")
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(.regularMaterial))
        } else {
            VStack(alignment: .leading, spacing: 3) {
                Text(date.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                ForEach(visible) { line in
                    HStack(spacing: 6) {
                        Circle().fill(line.color).frame(width: 6, height: 6)
                        if visible.count > 1 { Text(line.name).foregroundStyle(.secondary) }
                        Spacer(minLength: 8)
                        Text(SeriesStats.nearest(to: date, in: line.points).map { unit.format($0.value) } ?? "—")
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                    .font(.system(size: 11))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(minWidth: visible.count > 1 ? 130 : 80)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.regularMaterial))
            .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
        }
    }

    private var accessibilitySummary: String {
        visible.compactMap { line in
            SeriesStats(line.points).map { "\(line.name) now \(unit.format($0.latest)), peak \(unit.format($0.maximum.value))" }
        }.joined(separator: "; ")
    }
}

private struct OptionalReveal: ViewModifier {
    var enabled: Bool
    func body(content: Content) -> some View {
        if enabled { content.chartReveal() } else { content }
    }
}

/// Invoiced and collected per month as grouped bars, with a hover readout.
struct MonthBarsChart: View {
    var months: [BillingMonth]
    var currency: String
    var showInvoiced = true
    var showCollected = true
    var expanded = false

    @State private var hoverMonth: Date?

    var body: some View {
        Chart {
            ForEach(months) { month in
                if showInvoiced {
                    BarMark(x: .value("Month", month.month, unit: .month), y: .value("Amount", Money.plain(month.invoiced)))
                        .foregroundStyle(by: .value("Kind", "Invoiced"))
                        .position(by: .value("Kind", "Invoiced"))
                        .opacity(hoverMonth == nil || hoverMonth == month.month ? 1 : 0.45)
                }
                if showCollected {
                    BarMark(x: .value("Month", month.month, unit: .month), y: .value("Amount", Money.plain(month.collected)))
                        .foregroundStyle(by: .value("Kind", "Collected"))
                        .position(by: .value("Kind", "Collected"))
                        .opacity(hoverMonth == nil || hoverMonth == month.month ? 1 : 0.45)
                }
            }
            if let hoverMonth, let month = months.first(where: { $0.month == hoverMonth }) {
                RuleMark(x: .value("Month", month.month, unit: .month))
                    .foregroundStyle(.clear)
                    .annotation(position: .top, spacing: 2, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(month.month.formatted(.dateTime.month(.wide).year())).font(.system(size: 10)).foregroundStyle(.secondary)
                            row("Invoiced", Vivid.indigo, month.invoiced)
                            row("Collected", Vivid.green, month.collected)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.regularMaterial))
                        .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
                    }
            }
        }
        .chartForegroundStyleScale(["Invoiced": Vivid.indigo, "Collected": Vivid.green])
        .chartLegend(expanded ? .visible : .hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: .month, count: expanded ? 1 : 2)) { AxisValueLabel(format: .dateTime.month(.abbreviated)) }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(.quaternary)
                if expanded { AxisValueLabel { if let number = value.as(Double.self) { Text(Money.string(Int(number * 100), currency: currency)) } } }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            guard let plot = proxy.plotFrame else { return }
                            let x = location.x - geometry[plot].origin.x
                            guard let date: Date = proxy.value(atX: x) else { return }
                            hoverMonth = months.min { abs($0.month.timeIntervalSince(date)) < abs($1.month.timeIntervalSince(date)) }?.month
                        case .ended:
                            hoverMonth = nil
                        }
                    }
            }
        }
        .animation(.easeOut(duration: 0.15), value: hoverMonth)
        .chartReveal()
        .accessibilityLabel("Invoiced and collected per month")
    }

    private func row(_ name: String, _ color: Color, _ amount: Int) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(name).foregroundStyle(.secondary)
            Spacer(minLength: 10)
            Text(Money.string(amount, currency: currency)).fontWeight(.semibold).monospacedDigit()
        }
        .font(.system(size: 11))
    }
}

// MARK: - Expanding

/// The small button that opens a chart large.
struct ExpandChartButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 10, weight: .semibold))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help("Open this chart large")
        .accessibilityLabel("Expand chart")
    }
}

/// The frame of every expanded chart: title, controls, the chart and its statistics.
struct ExpandedChartSheet<Controls: View, ChartContent: View, Footer: View>: View {
    var title: String
    var subtitle: String?
    @ViewBuilder var controls: Controls
    @ViewBuilder var chart: ChartContent
    @ViewBuilder var footer: Footer
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 17, weight: .semibold))
                    if let subtitle { Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary) }
                }
                Spacer()
                controls
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            chart
                .frame(maxWidth: .infinity, minHeight: 340, maxHeight: .infinity)
                .padding(14)
                .card()
            footer
        }
        .padding(20)
        .frame(minWidth: 880, idealWidth: 1000, minHeight: 600, idealHeight: 660)
    }
}

/// Now, average, lowest and highest of each series, under an expanded chart.
struct SeriesStatsGrid: View {
    var series: [ChartSeries]
    var unit: ChartUnit

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
            GridRow {
                Text("")
                Text("Now"); Text("Average"); Text("Lowest"); Text("Highest")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            ForEach(series) { line in
                if let stats = SeriesStats(line.points) {
                    GridRow {
                        HStack(spacing: 6) {
                            Circle().fill(line.color).frame(width: 8, height: 8)
                            Text(line.name).fontWeight(.medium)
                        }
                        Text(unit.format(stats.latest))
                        Text(unit.format(stats.average))
                        Text("\(unit.format(stats.minimum.value)) · \(stats.minimum.date.formatted(.dateTime.day().month(.abbreviated).hour().minute()))")
                        Text("\(unit.format(stats.maximum.value)) · \(stats.maximum.date.formatted(.dateTime.day().month(.abbreviated).hour().minute()))")
                    }
                    .font(.system(size: 12))
                    .monospacedDigit()
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

/// Coloured toggles that show or hide series in an expanded chart.
struct SeriesToggles: View {
    var names: [(String, Color)]
    @Binding var hidden: Set<String>

    var body: some View {
        HStack(spacing: 6) {
            ForEach(names, id: \.0) { name, color in
                let on = !hidden.contains(name)
                Button {
                    if on { if hidden.count < names.count - 1 { hidden.insert(name) } } else { hidden.remove(name) }
                } label: {
                    HStack(spacing: 5) {
                        Circle().fill(on ? color : Color.secondary.opacity(0.4)).frame(width: 8, height: 8)
                        Text(name)
                    }
                    .font(.system(size: 12))
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(Capsule().fill(on ? color.opacity(0.14) : Color.clear))
                    .overlay(Capsule().strokeBorder(on ? color.opacity(0.35) : Color.secondary.opacity(0.25)))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
    }
}
