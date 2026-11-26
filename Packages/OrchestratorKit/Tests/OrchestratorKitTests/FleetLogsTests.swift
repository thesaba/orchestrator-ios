import Foundation
import Testing
@testable import OrchestratorKit

@Suite("Fleet server logs query")
struct FleetLogsTests {
    @Test func validatesLikeThePanel() {
        #expect(FleetLogsQuery(unit: "nginx.service").problem == nil)
        #expect(FleetLogsQuery(unit: "php8.3-fpm").problem == nil)
        #expect(FleetLogsQuery(unit: "bad unit").problem != nil)
        #expect(FleetLogsQuery(lines: 0).problem != nil)
        #expect(FleetLogsQuery(lines: 2001).problem != nil)
        #expect(FleetLogsQuery(source: .file, path: "/var/log/nginx/error.log").problem == nil)
        #expect(FleetLogsQuery(source: .file, path: "/etc/passwd").problem != nil)
        #expect(FleetLogsQuery(source: .file, path: "/var/log/../etc/shadow").problem != nil)
        #expect(FleetLogsQuery(source: .file, path: "/var/log/nginx/").problem != nil)
        #expect(FleetLogsQuery(grep: "a\nb").problem != nil)
    }

    @Test func buildsTheQuery() {
        let journal = FleetLogsQuery(unit: "mysql", lines: 300, grep: "error").queryItems(follow: true)
        #expect(journal.map(\.name) == ["source", "lines", "follow", "grep", "unit"])
        #expect(journal.first { $0.name == "unit" }?.value == "mysql")
        let file = FleetLogsQuery(source: .file, path: "/var/log/syslog").queryItems(follow: false)
        #expect(file.map(\.name) == ["source", "lines", "path"])
        #expect(file.first { $0.name == "source" }?.value == "file")
    }
}
