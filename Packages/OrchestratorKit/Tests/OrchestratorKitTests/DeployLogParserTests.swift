import Foundation
import Testing
@testable import OrchestratorKit

@Suite("Deploy log parsing")
struct DeployLogParserTests {
    static let failedLog = """
    [16:02:11] === Deploying branch 'main' to /var/www/sites/a.example ===
    [16:02:11] [1/8] Cloning repository...
    [16:02:13]   Commit: a41c9e2
    __COMMIT_MSG__:Fix invoice rounding
    __COMMIT_AUTHOR__:Saba
    [16:02:14] [2/8] Linking shared files...
    [16:02:15] [3/8] Installing PHP dependencies...
    [16:02:59] [3b/8] Tests enabled — installing dev dependencies...
    [16:03:10] [3b/8] Running tests: php artisan test
    [16:03:40]   ✓ Tests passed.
    [16:03:41] [3b/8] Pruning dev dependencies...
    [16:03:50] [4/8] No JS build step detected — skipping.
    [16:03:51] [5/8] Caching Laravel config, routes, views...
    [16:03:55] [6/8] Running migrations...
    [16:04:10] SQLSTATE[42S21]: Column already exists
    """

    @Test func stepsAndFacts() {
        let summary = DeployLogParser.parse(Self.failedLog, status: "failed")
        #expect(summary.totalSteps == 8)
        #expect(summary.steps.map(\.id) == ["1", "2", "3", "3b", "4", "5", "6"])
        #expect(summary.steps.first?.title == "Cloning repository")
        #expect(summary.commitMessage == "Fix invoice rounding")
        #expect(summary.commitAuthor == "Saba")
        #expect(summary.durationSeconds == 119)
        #expect(summary.steps[1].durationSeconds == 1)
        #expect(summary.steps[4].isSkipped)
        #expect(summary.steps[4].state == .skipped)
        #expect(summary.failedStep?.title == "Running migrations")
        #expect(summary.reachedActivation == false)
        #expect(summary.completed == false)
    }

    @Test func runningDeployProgress() {
        let log = """
        [12:00:01] [1/8] Cloning repository...
        [12:00:09] [2/8] Linking shared files...
        [12:00:10] [3/8] Installing PHP dependencies...
        """
        let summary = DeployLogParser.parse(log, status: "running")
        #expect(summary.currentStep?.number == 3)
        #expect(summary.currentStep?.state == .running)
        #expect(summary.progress == 2.5 / 8)
    }

    @Test func successAfterActivation() {
        let log = """
        [23:59:50] [6/8] Running migrations...
        [23:59:58] [7/8] Activating release (symlink swap)...
        [00:00:05] [8/8] Restarting queues and cleaning old releases...
        [00:00:09] === Deploy complete! ===
        __COMMIT__:a41c9e2
        [health] ✓ Health check passed
        """
        let summary = DeployLogParser.parse(log, status: "success")
        #expect(summary.completed)
        #expect(summary.reachedActivation)
        #expect(summary.healthCheckRan)
        #expect(summary.commit == "a41c9e2")
        // Crosses midnight without going negative.
        #expect(summary.durationSeconds == 19)
        #expect(summary.steps.allSatisfy { $0.state == .done })
    }

    @Test func ignoresBracketedTextThatIsNotAStep() {
        #expect(DeployLogParser.stepHeader(in: "[health] ok", startedAt: nil) == nil)
        #expect(DeployLogParser.stepHeader(in: "[42S21] no", startedAt: nil) == nil)
        #expect(DeployLogParser.stepHeader(in: "[0/8] zero", startedAt: nil) == nil)
        #expect(DeployLogParser.timestamp(in: "[1:2:3] x") == nil)
    }
}
