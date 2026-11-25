import AppIntents
import OrchestratorKit

/// Shortcuts actions that only read or open something.

struct FleetStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Fleet Status"
    static let description = IntentDescription("Summarises servers, sites and open alerts. Read-only.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let environment = try IntentSupport.environment()
        let store = environment.store
        if (store.lastUpdated.map { Date.now.timeIntervalSince($0) > 60 } ?? true) {
            await store.refresh(includeSiteList: false)
        }
        let summary = Self.summary(store.overview, error: store.lastError)
        return .result(value: summary, dialog: "\(summary)")
    }

    static func summary(_ overview: FleetOverview, error: String?) -> String {
        var parts = [overview.summary + "."]
        let servers = overview.serverCounts
        parts.append("\(servers.healthy) of \(servers.total) servers healthy, \(overview.siteCounts.up) of \(overview.siteCounts.total) sites up.")
        if overview.isDeploying { parts.append("\(overview.siteCounts.deploying) deploying.") }
        let alerts = overview.attention.prefix(3).map { "\($0.title) (\($0.source))" }
        if !alerts.isEmpty { parts.append(alerts.joined(separator: "; ") + ".") }
        if let error { parts.append("Some data could not be refreshed: \(error).") }
        return parts.joined(separator: " ")
    }
}

struct OpenDeployLogIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Deploy Log"
    static let description = IntentDescription("Opens the deploy log window of a site.")
    static let openAppWhenRun = true

    @Parameter(title: "Site")
    var site: SiteEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Open the deploy log of \(\.$site)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try IntentSupport.environment().open(.deployLog(siteID: site.id))
        return .result()
    }
}

/// Phrases for Siri, Spotlight and the Shortcuts gallery.
struct OrchestratorShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: FleetStatusIntent(),
                    phrases: ["Get \(.applicationName) status", "How is my fleet in \(.applicationName)"],
                    shortTitle: "Fleet Status", systemImageName: "server.rack")
        AppShortcut(intent: DeploySiteIntent(),
                    phrases: ["Deploy \(\.$site) with \(.applicationName)", "Deploy a site with \(.applicationName)"],
                    shortTitle: "Deploy Site", systemImageName: "arrow.up")
        AppShortcut(intent: OpenDeployLogIntent(),
                    phrases: ["Show the \(.applicationName) deploy log of \(\.$site)", "Open \(.applicationName) deploy log"],
                    shortTitle: "Deploy Log", systemImageName: "text.alignleft")
    }
}
