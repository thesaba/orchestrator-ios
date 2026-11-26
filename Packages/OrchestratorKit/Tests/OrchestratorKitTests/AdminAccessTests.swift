import Foundation
import Testing
@testable import OrchestratorKit

@Suite("Admin session, terminal sockets and fleet runs")
struct AdminAccessTests {
    @Test func readsJWTExpiry() {
        // {"userId":1,"exp":1795700000}
        let payload = Data(#"{"userId":1,"exp":1795700000}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "").replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        let jwt = "eyJhbGciOiJIUzI1NiJ9.\(payload).signature"
        #expect(AdminAccess.expiry(ofJWT: jwt) == Date(timeIntervalSince1970: 1_795_700_000))
        #expect(AdminAccess.expiry(ofJWT: "orch_notajwt") == nil)
    }

    @Test func buildsSocketURLs() {
        let base = URL(string: "https://panel.example")!
        let site = AdminAccess.socketURL(baseURL: base, path: "/terminal/9", token: "abc", query: [])
        #expect(site?.absoluteString == "wss://panel.example/api/terminal/9?token=abc")
        let server = AdminAccess.socketURL(baseURL: base, path: "/terminal/fleet/term/3", token: "a+b",
                                           query: [URLQueryItem(name: "cols", value: "120"), URLQueryItem(name: "rows", value: "30")])
        #expect(server?.scheme == "wss")
        #expect(server?.path == "/api/terminal/fleet/term/3")
        #expect(URLComponents(url: server!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "a+b")
    }

    @Test @MainActor func adoptedSessionIsSignedInUntilExpiry() {
        let access = AdminAccess(baseURL: URL(string: "https://panel.example")!)
        #expect(!access.isSignedIn)
        let future = Int(Date.now.timeIntervalSince1970) + 3600
        let payload = Data(#"{"exp":\#(future)}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "").replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        access.adopt(jwt: "h.\(payload).s", email: "a@b.ge")
        #expect(access.isSignedIn)
        #expect(!access.isElevated())
        #expect(access.siteTerminalURL(siteID: 4)?.path == "/api/terminal/4")
        access.signOut()
        #expect(!access.isSignedIn)
        #expect(access.siteTerminalURL(siteID: 4) == nil)
    }

    @Test func runTaskLimits() {
        let script = FleetScript(id: 1, name: "Disk report", description: nil, body: "df -h", timeoutSecs: 60, aiAllowed: false)
        #expect(FleetRunTask.script(script).problem(serverCount: 2) == nil)
        #expect(FleetRunTask.script(script).problem(serverCount: 0) != nil)
        #expect(FleetRunTask.script(script).problem(serverCount: 51) != nil)
        #expect(FleetRunTask.command("  ", timeoutSeconds: 60).problem(serverCount: 1) != nil)
        #expect(FleetRunTask.command("uptime", timeoutSeconds: 0).problem(serverCount: 1) != nil)
        #expect(FleetRunTask.command("uptime\nfree -m", timeoutSeconds: 60).title == "uptime")
    }

    @Test func serverSwitchesDecode() throws {
        let servers = try Fixtures.decode(FleetServersResponse.self, Fixtures.fleetServers).servers
        #expect(servers[0].terminalEnabled && servers[0].commandsEnabled)
        #expect(!servers[1].terminalEnabled && !servers[1].commandsEnabled)
    }
}
