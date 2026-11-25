import OrchestratorKit
import SwiftUI

/// Servers, Sites and Alerts: caption, large number, one-line breakdown.
struct SummaryTiles: View {
    let store: MonitorStore
    var select: (PopoverSegment) -> Void

    var body: some View {
        let overview = store.overview
        HStack(spacing: 8) {
            SummaryTile(caption: "Servers",
                        value: store.hasLoaded ? "\(overview.serverCounts.total)" : "—",
                        detail: store.hasLoaded ? overview.serverCounts.breakdown : " ") { select(.servers) }
            SummaryTile(caption: "Sites",
                        value: store.hasLoaded ? "\(overview.siteCounts.total)" : "—",
                        detail: store.hasLoaded ? overview.siteCounts.breakdown : " ") { select(.sites) }
            SummaryTile(caption: "Alerts",
                        value: store.hasLoaded ? "\(overview.alertCount)" : "—",
                        detail: store.hasLoaded ? overview.alertBreakdown : " ",
                        valueColor: overview.alertCount > 0 ? .statusWarningText : nil) { select(.alerts) }
        }
    }
}

private struct SummaryTile: View {
    var caption: String
    var value: String
    var detail: String
    var valueColor: Color?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 22, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(valueColor ?? .primary)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .card()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(caption): \(value)")
        .accessibilityValue(detail)
        .accessibilityHint("Shows all \(caption.lowercased())")
    }
}
