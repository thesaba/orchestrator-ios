import Foundation
import Testing
@testable import OrchestratorKit

@Suite("Deep links")
struct DeepLinkTests {
    @Test(arguments: [
        ("orchestrator://overview", DeepLink.popover(.overview)),
        ("orchestrator://alerts", .popover(.alerts)),
        ("ORCHESTRATOR://Servers", .popover(.servers)),
        ("orchestrator://settings", .settings),
        ("orchestrator://site/12/log", .deployLog(siteID: 12)),
        ("orchestrator://site/12/logs", .siteLogs(siteID: 12)),
        ("orchestrator://site/12", .site(siteID: 12)),
        ("orchestrator://server/5", .server(serverID: 5))
    ])
    func parses(text: String, expected: DeepLink) throws {
        let url = try #require(URL(string: text))
        #expect(DeepLink(url: url) == expected)
    }

    @Test(arguments: [
        "https://overview", "orchestrator://", "orchestrator://palette", "orchestrator://deploy/12", "orchestrator://site/abc/log",
        "orchestrator://site/0", "orchestrator://site/12/rollback", "orchestrator://overview/extra",
        "orchestrator://server/-3"
    ])
    func rejects(text: String) throws {
        let url = try #require(URL(string: text))
        #expect(DeepLink(url: url) == nil)
    }

    @Test func roundTrips() {
        let links: [DeepLink] = DeepLink.Segment.allCases.map { .popover($0) }
            + [.settings, .deployLog(siteID: 3), .siteLogs(siteID: 3), .site(siteID: 3), .server(serverID: 9)]
        for link in links {
            #expect(DeepLink(url: link.url) == link)
        }
    }
}
