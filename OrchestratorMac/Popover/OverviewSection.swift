import OrchestratorKit
import SwiftUI

/// Needs attention (when there is any), up to four servers and up to three sites.
struct OverviewSection: View {
    let environment: AppEnvironment
    var select: (PopoverSegment) -> Void

    private static let attentionLimit = 4
    private static let serverLimit = 4
    private static let siteLimit = 3

    var body: some View {
        let overview = environment.store.overview
        VStack(alignment: .leading, spacing: 12) {
            if !overview.attention.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    SectionHeader(
                        title: "Needs attention",
                        trailing: overview.attention.count > Self.attentionLimit ? "All \(overview.attention.count)" : nil
                    ) { select(.alerts) }
                    AttentionList(environment: environment,
                                  items: Array(overview.attention.prefix(Self.attentionLimit)))
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                SectionHeader(title: "Servers", trailing: "All \(overview.serverCounts.total)") { select(.servers) }
                ServerList(environment: environment, servers: Array(overview.servers.prefix(Self.serverLimit)))
            }

            VStack(alignment: .leading, spacing: 6) {
                SectionHeader(title: "Sites", trailing: "All \(overview.siteCounts.total)") { select(.sites) }
                SiteList(environment: environment, sites: Array(overview.sites.prefix(Self.siteLimit)))
            }
        }
    }
}
