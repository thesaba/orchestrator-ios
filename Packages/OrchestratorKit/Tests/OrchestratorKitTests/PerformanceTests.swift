import Foundation
import Testing
@testable import OrchestratorKit

@Suite("Incremental parsing and the site list digest")
struct PerformanceTests {
    @Test func accumulatorMatchesWholeTextParse() {
        let log = DeployLogParserTests.failedLog
        var accumulator = DeployLogAccumulator()
        for line in log.split(separator: "\n") { accumulator.consume(line) }
        #expect(accumulator.summary(status: "failed") == DeployLogParser.parse(log, status: "failed"))
        // Reading the summary while running does not consume anything twice.
        #expect(accumulator.summary(status: "running").steps.count == 7)
    }

    @Test func digestDropsLogsAndKeepsSummaries() throws {
        let listings = try Fixtures.decode([SiteListing].self, Fixtures.sites)
        let digest = SiteListDigest(listings)
        #expect(digest.sites.allSatisfy { $0.deployments.allSatisfy { $0.log == nil } })
        #expect(digest.summaries[10]?.currentStep?.title == "Installing PHP dependencies")
        #expect(digest.summaries[11] == nil) // its newest deployment had no log
        #expect(digest.sites.map(\.id) == listings.map(\.id))
    }

    @Test func aggregatorUsesDigestSummaries() throws {
        let digest = SiteListDigest(try Fixtures.decode([SiteListing].self, Fixtures.sites))
        let overview = StatusAggregator().overview(
            servers: [], alerts: [], certificates: [], uptime: [],
            sites: digest.sites, deploySummaries: digest.summaries, now: Fixtures.now)
        #expect(overview.sites.first?.deploy?.currentStep?.number == 3)
    }

    /// 20 000 lines fed one at a time, as a live deploy does: linear, so well under a second.
    @Test(.timeLimit(.minutes(1)))
    func largeLiveLogStaysLinear() {
        var accumulator = DeployLogAccumulator()
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for index in 0..<20_000 {
                let step = index % 2_500 == 0 ? " [\(index / 2_500 + 1)/8] Step \(index)" : " output line \(index)"
                accumulator.consume("[12:\(String(format: "%02d", (index / 60) % 60)):\(String(format: "%02d", index % 60))]\(step)")
                if index % 50 == 0 { _ = accumulator.summary(status: "running") }
            }
        }
        #expect(accumulator.summary(status: "running").steps.count == 8)
        #expect(elapsed < .seconds(2))
    }
}
