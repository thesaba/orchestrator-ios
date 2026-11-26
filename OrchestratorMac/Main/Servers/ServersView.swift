import OrchestratorKit
import SwiftUI

/// The fleet, worst first: CPU, RAM and disk per server. Double-click or Return opens a
/// server's page.
struct ServersView: View {
    let environment: AppEnvironment
    @Bindable var model: MainWindowModel

    private var store: MonitorStore { environment.store }

    var body: some View {
        if let id = model.openServerID {
            ServerDetailView(environment: environment, model: model, serverID: id)
        } else {
            list
        }
    }

    private var servers: [ServerStatus] {
        let query = model.searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return store.overview.servers }
        return store.overview.servers.filter {
            [$0.server.name, $0.server.host ?? "", $0.server.location ?? "", $0.server.provider ?? ""]
                .contains { $0.lowercased().contains(query) }
        }
    }

    private var list: some View {
        let servers = self.servers
        return VStack(spacing: 0) {
            tiles
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            Divider()
            ServerColumnsHeader()
            Divider()
            if !store.hasLoaded {
                SkeletonRows(count: 4, rowHeight: 40).padding(16)
                Spacer()
            } else if servers.isEmpty {
                ContentUnavailableView(store.servers.isEmpty ? "No servers" : "No matching servers", systemImage: "server.rack",
                                       description: Text(store.servers.isEmpty ? "Fleet monitoring needs an admin account." : "Nothing matches “\(model.searchText)”."))
                    .frame(maxHeight: .infinity)
            } else {
                List(selection: $model.selectedServerID) {
                    ForEach(servers) { status in
                        ServerRowView(status: status)
                            .tag(status.id)
                            .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                            .rightClickMenu { RowMenus.server(status.server, environment: environment) }
                            .appearIn(delay: 0.03)
                            .help("Double-click to open \(status.server.name)")
                    }
                }
                .listStyle(.inset)
                .contextMenu(forSelectionType: Int.self) { _ in } primaryAction: { ids in
                    if let id = ids.first { model.openServer(id) }
                }
            }
        }
    }

    @ViewBuilder
    private var tiles: some View {
        if store.hasLoaded { loadedTiles } else { SkeletonTiles() }
    }

    private var loadedTiles: some View {
        let servers = store.overview.servers.map(\.server)
        func average(_ values: [Double?]) -> String {
            let known = values.compactMap { $0 }
            return known.isEmpty ? "—" : "\(Int((known.reduce(0, +) / Double(known.count)).rounded()))%"
        }
        let fullest = servers.max { ($0.diskPercent ?? 0) < ($1.diskPercent ?? 0) }
        let counts = store.overview.serverCounts
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
            tile("Healthy", counts.total == 0 ? "—" : "\(counts.healthy) / \(counts.total)", counts.breakdown,
                 tint: counts.failure > 0 ? .statusDangerText : nil)
            tile("Average CPU", average(servers.map(\.cpuPercent)), "now")
            tile("Average RAM", average(servers.map(\.ramPercent)), "now")
            tile("Fullest disk", fullest?.diskPercent.map { "\(Int($0.rounded()))%" } ?? "—", fullest?.name ?? "",
                 tint: (fullest?.diskPercent ?? 0) >= 90 ? .statusWarningText : nil)
        }
    }

    private func tile(_ caption: String, _ value: String, _ detail: String, tint: Color? = nil) -> some View {
        let icons: [String: (String, Color)] = [
            "Healthy": ("heart.fill", Vivid.green), "Average CPU": ("cpu", Vivid.indigo),
            "Average RAM": ("memorychip", Vivid.teal), "Fullest disk": ("internaldrive.fill", Vivid.orange)
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
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .card()
        .accessibilityElement(children: .combine)
    }
}

enum ServerColumns {
    static let mark: CGFloat = 16
    static let meter: CGFloat = 130
    static let load: CGFloat = 54
    static let sites: CGFloat = 44
    static let status: CGFloat = 120
}

private struct ServerColumnsHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            Spacer().frame(width: ServerColumns.mark, height: 1)
            Text("Server").frame(minWidth: 160, maxWidth: .infinity, alignment: .leading)
            Text("CPU").frame(width: ServerColumns.meter, alignment: .leading)
            Text("RAM").frame(width: ServerColumns.meter, alignment: .leading)
            Text("Disk").frame(width: ServerColumns.meter, alignment: .leading)
            Text("Load").frame(width: ServerColumns.load, alignment: .trailing)
            Text("Sites").frame(width: ServerColumns.sites, alignment: .trailing)
            Text("Status").frame(width: ServerColumns.status, alignment: .trailing)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 24)
        .padding(.vertical, 6)
        .accessibilityHidden(true)
    }
}

struct ServerRowView: View {
    var status: ServerStatus
    private var server: FleetServer { status.server }

    var body: some View {
        HStack(spacing: 12) {
            StatusMarkView(mark: status.mark, size: ServerColumns.mark)
            VStack(alignment: .leading, spacing: 1) {
                Text(server.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(minWidth: 160, maxWidth: .infinity, alignment: .leading)
            MeterCell(percent: server.cpuPercent, warn: 80, bad: 95)
            MeterCell(percent: server.ramPercent, warn: 85, bad: 95)
            MeterCell(percent: server.diskPercent, warn: 80, bad: 90)
            Text(server.latest?.m.cpu.load1.map { String(format: "%.2f", $0) } ?? "—")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: ServerColumns.load, alignment: .trailing)
            Text("\(server.siteCount)")
                .foregroundStyle(.secondary)
                .frame(width: ServerColumns.sites, alignment: .trailing)
            Text(status.label)
                .font(.system(size: 12))
                .foregroundStyle(status.mark == .healthy ? Color.statusSuccessText : status.mark.textTint)
                .lineLimit(1)
                .frame(width: ServerColumns.status, alignment: .trailing)
        }
        .font(.system(size: 13))
        .frame(height: 40)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(server.name)
        .accessibilityValue("\(status.label), CPU \(percent(server.cpuPercent)), RAM \(percent(server.ramPercent)), disk \(percent(server.diskPercent))")
    }

    private var subtitle: String {
        [server.location, server.provider, server.isLocal ? "panel host" : server.channel].compactMap { $0 }
            .filter { !$0.isEmpty && $0 != "none" }.joined(separator: " · ")
    }

    private func percent(_ value: Double?) -> String { value.map { "\(Int($0.rounded())) percent" } ?? "no data" }
}

/// A bar with the percentage beside it, orange and red past the thresholds.
struct MeterCell: View {
    var percent: Double?
    var warn: Double
    var bad: Double

    var body: some View {
        let value = percent ?? 0
        let tint: Color = value >= bad ? .statusDanger : (value >= warn ? .statusWarning : .accentColor)
        HStack(spacing: 8) {
            ProgressBar(fraction: value / 100, tint: tint, height: 6)
            Text(percent.map { "\(Int($0.rounded()))%" } ?? "—")
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(value >= warn ? (value >= bad ? Color.statusDangerText : Color.statusWarningText) : .secondary)
                .frame(width: 36, alignment: .trailing)
        }
        .frame(width: ServerColumns.meter)
    }
}
