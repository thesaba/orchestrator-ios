import Foundation
import Testing
@testable import OrchestratorKit

@Suite("Dashboard, site table and fleet charts")
struct DashboardTests {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func overview() throws -> FleetOverview {
        StatusAggregator(sslWarningDays: 14).overview(
            servers: try Fixtures.decode(FleetServersResponse.self, Fixtures.fleetServers).servers,
            alerts: try Fixtures.decode(FleetAlertsResponse.self, Fixtures.fleetAlerts).events,
            certificates: try Fixtures.decode(SSLOverview.self, Fixtures.sslOverview).sites,
            uptime: try Fixtures.decode(UptimeOverview.self, Fixtures.uptime).sites,
            sites: try Fixtures.decode([SiteListing].self, Fixtures.sites),
            now: Fixtures.now)
    }

    @Test func tilesCountTodaysDeploysPlusTheRunningOne() throws {
        let summary = DashboardSummary.make(
            overview: try overview(),
            deployStats: try Fixtures.decode(DeployStatsHistory.self, Fixtures.deployStats),
            apm: try Fixtures.decode(APMOverview.self, Fixtures.apm),
            uptime: try Fixtures.decode(UptimeOverview.self, Fixtures.uptime).sites,
            now: Fixtures.now, calendar: utc)
        let tiles = Dictionary(uniqueKeysWithValues: summary.tiles.map { ($0.kind, $0) })
        #expect(tiles[.deploys]?.value == "7")
        #expect(tiles[.deploys]?.detail == "5 succeeded · 1 failed · 1 running")
        #expect(tiles[.deploys]?.emphasis == .warning)
        #expect(tiles[.servers]?.value == "0 / 2")
        #expect(tiles[.alerts]?.value == "3")
        #expect(tiles[.alerts]?.emphasis == .failure)
        #expect(tiles[.sites]?.detail == "0 up · 1 deploying · 1 down")
    }

    @Test func timelinePutsTheRunningDeployFirst() throws {
        let summary = DashboardSummary.make(overview: try overview(), deployStats: nil, apm: nil,
                                            uptime: [], now: Fixtures.now, calendar: utc)
        #expect(summary.recentDeploys.map(\.domain) == ["a.example", "b.example"])
        #expect(summary.recentDeploys[0].outcome == .running)
        #expect(summary.recentDeploys[0].currentStep?.title == "Installing PHP dependencies")
        #expect(summary.recentDeploys[1].outcome == .succeeded)
        #expect(summary.recentDeploys[1].shortCommit == "a41c9e2")
        #expect(summary.tiles.first { $0.kind == .deploys }?.value == "1")
    }

    @Test func uptimeRowsAreWorstFirstAndSkipUnmonitoredSites() throws {
        let summary = DashboardSummary.make(
            overview: try overview(), deployStats: nil,
            apm: try Fixtures.decode(APMOverview.self, Fixtures.apm),
            uptime: try Fixtures.decode(UptimeOverview.self, Fixtures.uptime).sites,
            now: Fixtures.now, calendar: utc)
        #expect(summary.uptimeRows.map(\.domain) == ["b.example", "a.example"])
        #expect(summary.uptimeRows[0].mark == .failure)
        #expect(summary.uptimeRows[1].p95 == 212)
        #expect(summary.uptimeRows[1].mark == .deploying)
    }

    @Test func siteTableNamesServersAndFilters() throws {
        let overview = try overview()
        let listings = try Fixtures.decode([SiteListing].self, Fixtures.sites)
        let servers = try Fixtures.decode(FleetServersResponse.self, Fixtures.fleetServers).servers
        let apm = try Fixtures.decode(APMOverview.self, Fixtures.apm)
        func rows(_ filter: SiteFilter, _ search: String = "") -> [SiteTableRow] {
            SiteTable.rows(overview: overview, listings: listings, servers: servers, apm: apm, filter: filter, search: search)
        }
        let all = rows(.all)
        #expect(all.map(\.name) == ["Alpha", "Beta", "Gamma"])
        // A null serverId runs on the panel host.
        #expect(all[0].serverName == "panel")
        #expect(all[1].serverName == "relay")
        #expect(all[1].isStaging)
        #expect(all[0].lastDeployText(now: Fixtures.now) == "Deploying 3/8")
        #expect(rows(.staging).map(\.name) == ["Beta"])
        #expect(rows(.production).map(\.name) == ["Alpha", "Gamma"])
        // Beta is down, Alpha's certificate has 6 days left.
        #expect(rows(.problems).map(\.name) == ["Alpha", "Beta"])
        #expect(rows(.all, "RELAY").map(\.name) == ["Beta"])
        #expect(rows(.all, "  c.exa ").map(\.name) == ["Gamma"])
    }

    @Test func averagerWeighsServersEquallyAndSkipsEmptySlots() {
        let start = Fixtures.now
        func point(_ minutes: Double, _ cpu: Double) -> FleetMetricsHistory.Point {
            .init(t: start.addingTimeInterval(minutes * 60), cpu: cpu, ram: cpu, disk: 50)
        }
        // Server A samples twice in the first slot, B once; slot 2 is empty; slot 3 only A.
        let a = [point(1, 10), point(2, 30), point(25, 80)]
        let b = [point(5, 60)]
        let points = ResourceAverager.average([a, b], from: start, to: start.addingTimeInterval(30 * 60), buckets: 3)
        #expect(points.count == 2)
        #expect(points[0].cpu == 40)          // mean(mean(10, 30), 60)
        #expect(points[1].cpu == 80)
        #expect(points[0].date == start.addingTimeInterval(5 * 60))
        #expect(ResourceAverager.peak(points, \.cpu)?.value == 80)
        #expect(ResourceAverager.change(points, \.cpu) == 40)
        #expect(ResourceAverager.average([a], from: start, to: start, buckets: 3).isEmpty)
    }

    @Test func metricsHistoryDecodes() throws {
        let json = #"{"points":[{"t":"2026-11-25T11:00:00.000Z","cpu":12.5,"ram":40,"disk":61.2,"swap":null,"load1":0.42,"rx":null,"tx":null,"dr":null,"dw":null}]}"#
        let history = try Fixtures.decode(FleetMetricsHistory.self, json)
        #expect(history.points.first?.disk == 61.2)
        #expect(history.points.first?.load1 == 0.42)
    }
}
