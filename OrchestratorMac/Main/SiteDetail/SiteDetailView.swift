import OrchestratorKit
import SwiftUI

/// One site's page: breadcrumb, name and main actions, the tabs, and the selected tab.
struct SiteDetailView: View {
    let environment: AppEnvironment
    @Bindable var model: MainWindowModel
    let siteID: Int

    private var store: MonitorStore { environment.store }

    private var row: SiteTableRow? {
        SiteTable.rows(overview: store.overview, listings: store.siteListings, servers: store.servers,
                       apm: model.data.apm, sslWarningDays: AppSettings.sslWarningDays)
            .first { $0.id == siteID }
    }

    var body: some View {
        if let row {
            VStack(spacing: 0) {
                SiteHeader(environment: environment, model: model, row: row)
                SiteTabBar(selection: $model.siteTab)
                Divider()
                content(row)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        model.closeSite()
                    } label: {
                        Label("Sites", systemImage: "chevron.left")
                    }
                    .help("Back to all sites")
                    .keyboardShortcut("[", modifiers: .command)
                }
            }
        } else {
            ContentUnavailableView {
                Label("Site not found", systemImage: "globe")
            } description: {
                Text(store.siteListings == nil ? "Loading the site list…" : "This site is no longer in the panel.")
            } actions: {
                Button("Back to Sites") { model.closeSite() }
            }
        }
    }

    @ViewBuilder
    private func content(_ row: SiteTableRow) -> some View {
        switch model.siteTab {
        case .overview: SiteOverviewTab(environment: environment, model: model, row: row)
        case .deploys:  SiteDeploysTab(environment: environment, row: row)
        case .config:   SiteConfigTab(environment: environment, siteID: row.id)
        case .ssl:      SiteSSLTab(environment: environment, row: row)
        case .workers:  SiteWorkersTab(environment: environment, siteID: row.id)
        case .logs:     SiteLogsTab(environment: environment, row: row)
        case .artisan:  SiteArtisanTab(environment: environment, siteID: row.id)
        case .files:    SiteFilesTab(environment: environment, siteID: row.id)
        case .database: SiteDatabaseTab(environment: environment, siteID: row.id)
        case .security: SiteSecurityTab(environment: environment, row: row)
        }
    }
}

/// "Sites › domain", the site's name, state and the actions used most.
private struct SiteHeader: View {
    let environment: AppEnvironment
    let model: MainWindowModel
    var row: SiteTableRow

    private var listing: SiteListing? { environment.store.siteListings?.first { $0.id == row.id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                Button("Sites") { model.closeSite() }
                    .buttonStyle(.link)
                Text("›").foregroundStyle(.tertiary)
                Text(row.domain).foregroundStyle(.secondary)
            }
            .font(.system(size: 12))

            HStack(spacing: 12) {
                Text(String(row.domain.prefix(1)).uppercased())
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.accentText)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.tintInfo))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.domain)
                        .font(.system(size: 18, weight: .semibold))
                        .textSelection(.enabled)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                StateBadge(row: row)
                Spacer(minLength: 12)
                Button("Open Site") {
                    if let url = URL(string: "https://\(row.domain)") { NSWorkspace.shared.open(url) }
                }
                Button(row.maintenanceMode ? "End Maintenance…" : "Maintenance…") {
                    let id = row.id, enable = !row.maintenanceMode
                    let executor = environment.executor
                    Task { await executor.setMaintenance(siteID: id, enable: enable) }
                }
                .help("Asks for confirmation and Touch ID")
                Button(row.isDeploying ? "Deploying…" : "Deploy…") {
                    let id = row.id
                    let executor = environment.executor
                    Task { await executor.deploy(siteID: id, ref: nil) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(row.isDeploying)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    private var subtitle: String {
        var parts: [String] = []
        if row.name.caseInsensitiveCompare(row.domain) != .orderedSame { parts.append(row.name) }
        if let php = listing?.phpVersion { parts.append("PHP \(php)") }
        if let server = row.serverName { parts.append(server) }
        if let branch = row.branch { parts.append("branch \(branch)") }
        return parts.joined(separator: " · ")
    }
}

/// "Live", "Deploying 4/7", "Down", "Maintenance" as a coloured capsule.
struct StateBadge: View {
    var row: SiteTableRow

    var body: some View {
        let (text, tint, fill) = style
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(Capsule().fill(fill))
    }

    private var style: (String, Color, Color) {
        if row.billingSuspended { return ("Suspended", .statusDangerText, .tintDanger) }
        if row.maintenanceMode { return ("Maintenance", .statusWarningText, .tintWarning) }
        switch row.mark {
        case .deploying: return (row.lastDeployText(), .accentText, .tintInfo)
        case .failure:   return (row.label, .statusDangerText, .tintDanger)
        case .warning:   return (row.label, .statusWarningText, .tintWarning)
        case .healthy:   return ("Live", .statusSuccessText, .tintSuccess)
        case .unknown:   return (row.label, .secondary, Color.secondary.opacity(0.15))
        }
    }
}

/// The tabs, underlined when selected.
private struct SiteTabBar: View {
    @Binding var selection: SiteTab

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 2) {
                ForEach(SiteTab.allCases) { tab in
                    Button {
                        selection = tab
                    } label: {
                        Text(tab.title)
                            .font(.system(size: 12, weight: selection == tab ? .semibold : .regular))
                            .foregroundStyle(selection == tab ? .primary : .secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .overlay(alignment: .bottom) {
                                Rectangle()
                                    .fill(selection == tab ? Color.accentColor : .clear)
                                    .frame(height: 2)
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(tab.title)
                    .accessibilityAddTraits(selection == tab ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, 14)
        }
        .scrollIndicators(.never)
    }
}
