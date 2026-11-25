import Foundation
import Testing
@testable import OrchestratorKit

@Suite("Decoding the responses the Mac app reads")
struct DecodingTests {
    @Test func fleetServers() throws {
        let response = try Fixtures.decode(FleetServersResponse.self, Fixtures.fleetServers)
        #expect(response.servers.count == 2)
        #expect(response.shippedAgentVersion == "1.4.0")

        let panel = try #require(response.servers.first)
        #expect(panel.isLocal)
        #expect(panel.location == "Frankfurt")
        #expect(panel.activeAlerts == 1)
        #expect(panel.cpuPercent == 34.2)
        #expect(panel.ramPercent.map { ($0 * 10).rounded() / 10 } == 61)
        // The root mount wins over a fuller /boot.
        #expect(panel.primaryDisk?.mount == "/")
        #expect(panel.diskPercent == 91)

        let relay = response.servers[1]
        #expect(relay.latest == nil)
        #expect(relay.tags == ["edge"])
        #expect(relay.agentStatus == "pending")
        #expect(relay.latencyMs == 12)
    }

    @Test func fleetAlerts() throws {
        let events = try Fixtures.decode(FleetAlertsResponse.self, Fixtures.fleetAlerts).events
        let alert = try #require(events.first)
        #expect(alert.kind == "disk")
        #expect(alert.value == 91)
        #expect(alert.isActive)
        #expect(alert.serverName == "panel")
    }

    @Test func siteListingsKeepNewestLogAndTolerateNulls() throws {
        let sites = try Fixtures.decode([SiteListing].self, Fixtures.sites)
        #expect(sites.count == 3)
        #expect(sites[0].isDeploying)
        #expect(sites[0].latestDeployment?.log?.contains("[3/8]") == true)
        // null booleans decode as false; missing optional fields as nil.
        #expect(sites[1].sslEnabled == false)
        #expect(sites[1].deployQueued == false)
        #expect(sites[1].latestDeployment?.shortCommit == "a41c9e2")
        #expect(sites[2].disabled)
        #expect(sites[2].latestDeployment == nil)
    }

    @Test func sslAndUptime() throws {
        let ssl = try Fixtures.decode(SSLOverview.self, Fixtures.sslOverview)
        #expect(ssl.sites.map(\.daysLeft) == [6, 70])
        let uptime = try Fixtures.decode(UptimeOverview.self, Fixtures.uptime)
        #expect(uptime.sites.count == 3)
        #expect(uptime.sites[1].isUp == false)
        #expect(uptime.sites[2].checkedAt == nil)
    }

    @Test func deployNotificationMeta() throws {
        let json = """
        {"notifications": [{"id": 102, "type": "deploy", "level": "success",
          "title": "Deploy succeeded — a.example", "body": "main @ 2a37f7d — Merge",
          "meta": "{\\"siteId\\":10,\\"domain\\":\\"a.example\\"}", "read": false,
          "createdAt": "2026-08-02T00:20:07.664Z"}], "unread": 1}
        """
        let response = try Fixtures.decode(NotificationsResponse.self, json)
        let item = try #require(response.notifications.first)
        #expect(item.siteId == 10)
        #expect(item.domain == "a.example")
    }
}
