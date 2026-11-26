import OrchestratorKit
import SwiftUI

/// Sidebar of sections on the left, the selected section on the right, search and refresh in
/// the toolbar. Follows the system's light or dark appearance.
struct MainView: View {
    let environment: AppEnvironment
    @Bindable var model: MainWindowModel

    private var store: MonitorStore { environment.store }

    var body: some View {
        NavigationSplitView {
            SidebarView(environment: environment, model: model)
                .navigationSplitViewColumnWidth(min: 200, ideal: 224, max: 300)
        } detail: {
            detail
                .navigationTitle(title)
                .navigationSubtitle(subtitle)
        }
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "Search sites and servers")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    environment.scheduler.refreshNow()
                    model.data.refreshAll()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .symbolEffect(.rotate, options: .repeating, isActive: store.isRefreshing)
                }
                .help("Refresh now")
                .disabled(environment.session.phase != .signedIn)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }

    @ViewBuilder
    private var detail: some View {
        switch environment.session.phase {
        case .launching:
            ProgressView().controlSize(.small)
        case .signedOut:
            ContentUnavailableView {
                Label("Sign in to Orchestrator", systemImage: "person.crop.circle")
            } description: {
                Text("Use an API token from the web panel’s Settings page.")
            } actions: {
                Button("Sign In…") { environment.windows.showSignIn() }
                    .buttonStyle(.borderedProminent)
            }
        case .signedIn:
            switch model.selection ?? .dashboard {
            case .dashboard: DashboardView(environment: environment, model: model)
            case .alerts:    AlertsView(environment: environment)
            case .sites:     SitesView(environment: environment, model: model)
            case .servers:   ServersView(environment: environment, model: model)
            case .monitoring: MonitoringView(environment: environment, model: model)
            case .billing:   BillingView(environment: environment)
            case .tasks:     TasksNotesView(environment: environment, model: model)
            case .assistant: AssistantView(environment: environment)
            case .users:     UsersAccessView(environment: environment)
            case .audit:     AuditLogView(environment: environment, model: model)
            case .automation: AutomationView(environment: environment)
            }
        }
    }

    private var title: String {
        if model.selection == .sites, let id = model.openSiteID, let site = store.site(id: id) {
            return site.domain
        }
        if model.selection == .servers, let id = model.openServerID, let server = store.server(id: id) {
            return server.server.name
        }
        return (model.selection ?? .dashboard).title
    }

    private var subtitle: String {
        guard environment.session.phase == .signedIn else { return "" }
        guard store.hasLoaded else { return "Loading…" }
        switch model.selection ?? .dashboard {
        case .sites where model.openSiteID != nil:
            return model.siteTab.title
        case .servers where model.openServerID != nil:
            return model.openServerID.flatMap { store.server(id: $0)?.label } ?? ""
        case .servers:
            let counts = store.overview.serverCounts
            return "\(counts.total) servers · \(counts.breakdown)"
        case .sites:
            let counts = store.overview.siteCounts
            return "\(counts.total) sites · \(counts.breakdown)"
        default:
            var parts = [store.overview.summary]
            if let error = store.lastError {
                parts.append(error)
            } else if let updated = store.lastUpdated {
                parts.append("updated \(RelativeTime.ago(updated))")
            }
            return parts.joined(separator: " · ")
        }
    }
}
