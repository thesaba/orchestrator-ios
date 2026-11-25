import Foundation
import Testing
@testable import OrchestratorKit

@Suite("Status aggregation for the menu bar and popover")
struct StatusAggregatorTests {
    let aggregator = StatusAggregator(sslWarningDays: 14)

    private func overview(sites: Bool = true) throws -> FleetOverview {
        aggregator.overview(
            servers: try Fixtures.decode(FleetServersResponse.self, Fixtures.fleetServers).servers,
            alerts: try Fixtures.decode(FleetAlertsResponse.self, Fixtures.fleetAlerts).events,
            certificates: try Fixtures.decode(SSLOverview.self, Fixtures.sslOverview).sites,
            uptime: try Fixtures.decode(UptimeOverview.self, Fixtures.uptime).sites,
            sites: sites ? try Fixtures.decode([SiteListing].self, Fixtures.sites) : nil,
            now: Fixtures.now
        )
    }

    @Test func serversAreSortedWorstFirstAndLabelled() throws {
        let result = try overview()
        #expect(result.servers.map(\.server.name) == ["panel", "relay"])
        #expect(result.servers[0].mark == .warning)
        #expect(result.servers[0].label == "Disk 91%")
        #expect(result.servers[0].headlineMetric.name == "Disk")
        #expect(result.servers[1].mark == .unknown)
        #expect(result.servers[1].label == "Waiting for agent")
        #expect(result.serverCounts.breakdown == "0 healthy · 1 warning · 1 no data")
    }

    @Test func attentionCombinesAlertsDownSitesAndCertificates() throws {
        let result = try overview()
        #expect(result.attention.map(\.id) == ["down-11", "alert-41", "ssl-10"])
        #expect(result.attention.map(\.title) == ["Site down", "Disk at 91%", "SSL expires in 6 days"])
        #expect(result.alertBreakdown == "1 down · 1 disk · 1 SSL")
        #expect(result.summary == "3 items need attention")
    }

    @Test func deployingSiteComesFirstAndDrivesTheMenuBar() throws {
        let result = try overview()
        #expect(result.sites.first?.name == "Alpha")
        #expect(result.sites.first?.mark == .deploying)
        #expect(result.sites.first?.deploy?.currentStep?.title == "Installing PHP dependencies")
        #expect(result.siteCounts.deploying == 1)
        #expect(result.siteCounts.down == 1)
        #expect(result.menuBarMark == .deploying)
    }

    @Test func withoutTheSiteListUptimeStillCountsSites() throws {
        let result = try overview(sites: false)
        #expect(result.siteCounts.total == 3)
        #expect(result.siteCounts.up == 1)
        #expect(result.menuBarMark == .failure)
    }

    @Test func healthyFleetHasNoMark() {
        let server = FleetServer(
            id: 7, name: "web", agentStatus: "online", channel: "agent",
            latest: FleetLatestMetrics(at: Fixtures.now, source: "agent",
                                       m: FleetMetrics(cpu: .init(percent: 5), mem: .init(total: 100, used: 20))))
        let result = aggregator.overview(servers: [server], alerts: [], certificates: [], uptime: [], sites: [], now: Fixtures.now)
        #expect(result.servers.first?.mark == .healthy)
        #expect(result.menuBarMark == nil)
        #expect(result.summary == "All systems healthy")
        #expect(result.alertBreakdown == "None")
    }

    @Test func offlineAgentAndStaleMetrics() {
        let old = Fixtures.now.addingTimeInterval(-3_600)
        let metrics = FleetMetrics(cpu: .init(percent: 5), mem: .init(total: 100, used: 20))
        let offline = FleetServer(id: 1, name: "a", agentStatus: "offline", latest: .init(at: old, source: "agent", m: metrics))
        let stale = FleetServer(id: 2, name: "b", agentStatus: "none", channel: "ssh", latest: .init(at: old, source: "ssh", m: metrics))
        #expect(aggregator.serverStatus(offline, alerts: [], now: Fixtures.now).mark == .failure)
        #expect(aggregator.serverStatus(stale, alerts: [], now: Fixtures.now).label == "No recent data")
    }

    @Test func certificateThresholds() {
        func item(_ days: Int?) -> AttentionItem? {
            aggregator.certificateItem(.init(siteId: 1, domain: "x", daysLeft: days, expiresAt: nil, error: nil))
        }
        #expect(item(15) == nil)
        #expect(item(14)?.title == "SSL expires in 14 days")
        #expect(item(1)?.title == "SSL expires tomorrow")
        #expect(item(-2)?.severity == .failure)
        #expect(item(nil) == nil)
    }
}
