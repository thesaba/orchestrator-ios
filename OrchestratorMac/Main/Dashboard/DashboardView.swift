import OrchestratorKit
import SwiftUI

/// Tiles, then two columns: what needs attention and recent deploys on the left, fleet
/// resources and response times on the right. One column when the window is narrow.
struct DashboardView: View {
    let environment: AppEnvironment
    let model: MainWindowModel

    @State private var width: CGFloat = 1200

    private var store: MonitorStore { environment.store }
    private var data: MainDataStore { model.data }

    private var summary: DashboardSummary {
        DashboardSummary.make(overview: store.overview, deployStats: data.deployStats, apm: data.apm,
                              uptime: store.uptime)
    }

    var body: some View {
        let summary = self.summary
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !store.hasLoaded {
                    ProgressView("Loading…")
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    tiles(summary.tiles)
                    if width >= 980 {
                        HStack(alignment: .top, spacing: 16) {
                            leftColumn(summary)
                            rightColumn(summary)
                        }
                    } else {
                        leftColumn(summary)
                        rightColumn(summary)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        }
    }

    private func tiles(_ tiles: [DashboardSummary.Tile]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: width >= 720 ? 4 : 2), spacing: 12) {
            ForEach(tiles) { tile in
                DashboardTile(tile: tile) { open(tile.kind) }
            }
        }
    }

    private func leftColumn(_ summary: DashboardSummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Needs attention",
                              trailing: store.overview.attention.isEmpty ? nil : "All alerts") { model.selection = .alerts }
                AttentionList(environment: environment, items: Array(store.overview.attention.prefix(5)))
            }
            DeployTimelineCard(environment: environment, model: model, deploys: summary.recentDeploys)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func rightColumn(_ summary: DashboardSummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ResourcesCard(data: data, overview: store.overview)
            UptimeCard(model: model, rows: summary.uptimeRows)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func open(_ kind: DashboardSummary.Tile.Kind) {
        switch kind {
        case .servers: model.selection = .servers; model.openServerID = nil
        case .sites, .deploys: model.selection = .sites
        case .alerts: model.selection = .alerts
        }
    }
}

/// Caption, large value and a one-line breakdown. Clicking opens the matching section.
private struct DashboardTile: View {
    var tile: DashboardSummary.Tile
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(tile.caption)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(tile.value)
                    .font(.system(size: 26, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(tile.emphasis?.textTint ?? .primary)
                Text(tile.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .card()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(tile.caption): \(tile.value)")
        .accessibilityValue(tile.detail)
        .accessibilityAddTraits(.isButton)
    }
}

/// "2 m 14 s".
enum DurationText {
    static func short(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) s" }
        if seconds < 3_600 { return "\(seconds / 60) m \(seconds % 60) s" }
        return "\(seconds / 3_600) h \(seconds % 3_600 / 60) m"
    }
}
