import OrchestratorKit
import SwiftUI

/// Compact site table with a filter bar, and the selected site in the inspector.
struct SitesView: View {
    let environment: AppEnvironment
    @Bindable var model: MainWindowModel

    @State private var tableWidth: CGFloat = 800

    private var store: MonitorStore { environment.store }

    private var rows: [SiteTableRow] {
        SiteTable.rows(overview: store.overview, listings: store.siteListings, servers: store.servers,
                       apm: model.data.apm, filter: model.siteFilter, search: model.searchText,
                       sslWarningDays: AppSettings.sslWarningDays)
    }

    var body: some View {
        if let siteID = model.openSiteID {
            SiteDetailView(environment: environment, model: model, siteID: siteID)
        } else {
            table
        }
    }

    @ViewBuilder
    private var table: some View {
        let rows = self.rows
        let columns = SiteColumns(width: tableWidth)
        HStack(spacing: 0) {
        VStack(spacing: 0) {
            filterBar(count: rows.count)
            Divider()
            SiteColumnsHeader(columns: columns)
            Divider()
            if !store.hasLoaded {
                SkeletonRows(count: 8, rowHeight: 30).padding(16)
                Spacer()
            } else if rows.isEmpty {
                ContentUnavailableView(model.searchText.isEmpty ? "No sites" : "No matching sites",
                                       systemImage: "globe",
                                       description: Text(model.searchText.isEmpty ? "Nothing matches this filter." : "Nothing matches “\(model.searchText)”."))
                    .frame(maxHeight: .infinity)
            } else {
                List(selection: $model.selectedSiteID) {
                    ForEach(rows) { row in
                        SiteTableRowView(row: row, columns: columns)
                            .tag(row.id)
                            .help("Double-click to open \(row.domain)")
                            .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                            .rightClickMenu {
                                if let site = environment.store.site(id: row.id) {
                                    return RowMenus.site(site, environment: environment)
                                }
                                return NSMenu()
                            }
                    }
                }
                .listStyle(.inset)
                .alternatingRowBackgrounds(.disabled)
                // Double-click or Return opens the site's page. Right-click is handled by
                // `rightClickMenu`, so this menu stays empty.
                .contextMenu(forSelectionType: Int.self) { _ in } primaryAction: { ids in
                    if let id = ids.first { model.openSite(id) }
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { tableWidth = $0 }

        // A plain side panel instead of `.inspector`: it is simply there when the page opens,
        // with no slide-in, and fades when shown or hidden.
        if model.showsInspector {
            Divider()
            Group {
                if let id = model.selectedSiteID, let row = rows.first(where: { $0.id == id }) {
                    SiteInspector(environment: environment, model: model, row: row)
                        .id(row.id)
                } else {
                    ContentUnavailableView("No site selected", systemImage: "sidebar.right",
                                           description: Text("Select a site to see its details."))
                }
            }
            .frame(width: 320)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(.background)
            .transition(.opacity)
        }
        }
        .animation(.easeOut(duration: 0.15), value: model.showsInspector)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.showsInspector.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.right")
                }
                .help(model.showsInspector ? "Hide the inspector" : "Show the inspector")
            }
        }
        .onAppear { keepSelectionVisible(rows.map(\.id)) }
        // A search or filter that hides the selected site selects the first one shown.
        .onChange(of: rows.map(\.id)) { _, ids in keepSelectionVisible(ids) }
    }

    private func keepSelectionVisible(_ ids: [Int]) {
        if model.selectedSiteID.map({ !ids.contains($0) }) ?? true {
            model.selectedSiteID = ids.first
        }
    }

    private func filterBar(count: Int) -> some View {
        HStack(spacing: 10) {
            Picker("Filter", selection: $model.siteFilter) {
                ForEach(SiteFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Spacer()
            Text(count == 1 ? "1 site" : "\(count) sites")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button("Open Web Panel") { WebPanel.open(.home) }
                .controlSize(.small)
                .help("Adding sites happens in the web panel for now")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

/// Column widths shared by the header and the rows, and which columns fit.
struct SiteColumns: Equatable {
    static let mark: CGFloat = 16
    static let siteMin: CGFloat = 180
    static let server: CGFloat = 130
    static let branch: CGFloat = 80
    static let deploy: CGFloat = 112
    static let uptime: CGFloat = 56
    static let p95: CGFloat = 60
    static let ssl: CGFloat = 64

    var showsServer = true
    var showsP95 = true

    /// Drops p95 first, then the server, as the table gets narrower.
    init(width: CGFloat) {
        showsP95 = width >= 860
        showsServer = width >= 640
    }
}

private struct SiteColumnsHeader: View {
    var columns: SiteColumns

    var body: some View {
        HStack(spacing: 10) {
            Spacer().frame(width: SiteColumns.mark, height: 1)
            Text("Site").frame(minWidth: SiteColumns.siteMin, maxWidth: .infinity, alignment: .leading)
            if columns.showsServer { Text("Server").frame(width: SiteColumns.server, alignment: .leading) }
            Text("Branch").frame(width: SiteColumns.branch, alignment: .leading)
            Text("Last deploy").frame(width: SiteColumns.deploy, alignment: .leading)
            Text("Uptime").frame(width: SiteColumns.uptime, alignment: .trailing)
            if columns.showsP95 { Text("p95").frame(width: SiteColumns.p95, alignment: .trailing) }
            Text("SSL").frame(width: SiteColumns.ssl, alignment: .trailing)
        }
        .lineLimit(1)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 24)
        .padding(.vertical, 6)
        .accessibilityHidden(true)
    }
}

struct SiteTableRowView: View {
    var row: SiteTableRow
    var columns: SiteColumns

    var body: some View {
        HStack(spacing: 10) {
            StatusMarkView(mark: row.mark, size: SiteColumns.mark)
            HStack(spacing: 6) {
                Text(row.domain)
                    .font(.system(size: 13, weight: .medium))
                if row.name.caseInsensitiveCompare(row.domain) != .orderedSame {
                    Text(row.name)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                if row.isStaging { Tag(text: "Staging") }
                if row.maintenanceMode { Tag(text: "Maintenance", tint: .statusWarningText) }
                if row.billingSuspended { Tag(text: "Suspended", tint: .statusDangerText) }
            }
            .lineLimit(1)
            .frame(minWidth: SiteColumns.siteMin, maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            if columns.showsServer {
                Text(row.serverName ?? "—")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: SiteColumns.server, alignment: .leading)
            }
            Text(row.branch ?? "—")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: SiteColumns.branch, alignment: .leading)
            Text(row.lastDeployText())
                .font(.system(size: 12))
                .foregroundStyle(row.isDeploying ? Color.accentText : (row.lastDeployFailed ? Color.statusDangerText : .secondary))
                .lineLimit(1)
                .frame(width: SiteColumns.deploy, alignment: .leading)
            Text(row.uptimePercent.map { "\($0)%" } ?? "—")
                .foregroundStyle((row.uptimePercent ?? 100) < 99 ? Color.statusWarningText : .primary)
                .frame(width: SiteColumns.uptime, alignment: .trailing)
            if columns.showsP95 {
                Text(row.p95.map { "\($0) ms" } ?? "—")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: SiteColumns.p95, alignment: .trailing)
            }
            Text(sslText)
                .font(.system(size: 12))
                .foregroundStyle(sslWarning ? Color.statusWarningText : .secondary)
                .frame(width: SiteColumns.ssl, alignment: .trailing)
        }
        .font(.system(size: 13))
        .frame(height: 30)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.domain)
        .accessibilityValue("\(row.label), last deploy \(row.lastDeployText()), SSL \(sslText)")
    }

    private var sslText: String {
        guard row.sslEnabled else { return "Off" }
        return row.sslDaysLeft.map { $0 == 1 ? "1 day" : "\($0) days" } ?? "On"
    }

    private var sslWarning: Bool {
        row.sslEnabled && (row.sslDaysLeft ?? .max) <= AppSettings.sslWarningDays
    }
}

/// A small rounded label next to a site's name.
struct Tag: View {
    var text: String
    var tint: Color = .secondary

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(.fill.secondary))
    }
}
