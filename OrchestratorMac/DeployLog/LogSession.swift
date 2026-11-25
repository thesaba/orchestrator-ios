import Foundation
import Observation
import OrchestratorKit

/// One live attachment to a `/stream` route: a deploy, a rollback, an Artisan command or a
/// certificate renewal. Created only by a user action (running a command, "Show log").
@MainActor
@Observable
final class LogSession: Identifiable {
    enum Kind: Equatable {
        case deploy
        case rollback(release: String)
        case artisan(command: String)
        case certificate
    }

    enum State: Equatable {
        case connecting, running, succeeded, failed, cancelled
        /// The stream answered at once with `done` and nothing to show: nothing runs.
        case notRunning
    }

    let id = UUID()
    let siteID: Int
    let domain: String
    let kind: Kind
    var branch: String?
    var commit: String?
    var deploymentID: Int?
    let startedAt: Date
    let runner = StreamRunner()
    /// Set once the stream has finished.
    private(set) var finishedAt: Date?

    @ObservationIgnored private var accumulator = DeployLogAccumulator()
    /// Highest `LogLine.id` already fed to the accumulator.
    @ObservationIgnored private var consumedThrough = -1
    @ObservationIgnored private var cachedLineCount = -1
    @ObservationIgnored private var cachedState: State?
    @ObservationIgnored private var cachedSummary = DeployLogSummary()

    init(siteID: Int, domain: String, kind: Kind, branch: String? = nil, commit: String? = nil,
         deploymentID: Int? = nil, startedAt: Date = .now) {
        self.siteID = siteID
        self.domain = domain
        self.kind = kind
        self.branch = branch
        self.commit = commit
        self.deploymentID = deploymentID
        self.startedAt = startedAt
    }

    var lines: [LogLine] { runner.buffer.lines }
    var isDeployLike: Bool {
        switch kind {
        case .deploy, .rollback: return true
        default:                 return false
        }
    }

    var state: State {
        if runner.isStreaming { return lines.isEmpty ? .connecting : .running }
        switch runner.outcome {
        case .success?:   return .succeeded
        case .cancelled?: return .cancelled
        case .failed?:
            let idle = ["unknown", "running", "idle"].contains(runner.lastStatus ?? "")
            return idle && lines.isEmpty ? .notRunning : .failed
        case nil:
            return .connecting
        }
    }

    var isFinished: Bool { ![.connecting, .running].contains(state) }

    /// Steps and facts parsed from the lines so far. Only lines not seen before are parsed,
    /// so a long deploy stays O(lines) instead of re-reading the whole log per line.
    var summary: DeployLogSummary {
        let current = state
        let all = lines
        if all.count != cachedLineCount || current != cachedState {
            for line in all where line.id > consumedThrough {
                accumulator.consume(line.text)
                consumedThrough = line.id
            }
            let status: String
            switch current {
            case .succeeded:            status = "success"
            case .failed, .cancelled:   status = "failed"
            default:                    status = "running"
            }
            cachedSummary = accumulator.summary(status: status)
            cachedLineCount = all.count
            cachedState = current
        }
        return cachedSummary
    }

    /// "Deploying citynet.ge", "Deployed citynet.ge", "Deploy failed".
    var title: String {
        switch (kind, state) {
        case (.deploy, .succeeded):              return "Deployed \(domain)"
        case (.deploy, .failed):                 return "Deploy failed"
        case (.deploy, .cancelled):              return "Deploy cancelled"
        case (.deploy, .notRunning):             return "No deploy running · \(domain)"
        case (.deploy, _):                       return "Deploying \(domain)"
        case (.rollback, .succeeded):            return "Rolled back \(domain)"
        case (.rollback, .failed):               return "Rollback failed"
        case (.rollback, _):                     return "Rolling back \(domain)"
        case (.artisan(let command), .succeeded): return "Ran \(command)"
        case (.artisan(let command), .failed):   return "\(command) failed"
        case (.artisan(let command), _):         return "Running \(command)"
        case (.certificate, .succeeded):         return "Renewed SSL · \(domain)"
        case (.certificate, .failed):            return "SSL renewal failed"
        case (.certificate, _):                  return "Renewing SSL · \(domain)"
        }
    }

    /// "main · a41c9e2" for deploys, the domain otherwise.
    var subtitle: String {
        switch kind {
        case .deploy:
            let commitText = commit ?? summary.commit.map { String($0.prefix(7)) }
            return [branch, commitText].compactMap { $0 }.joined(separator: " · ")
        case .rollback(let release):
            return "to \(ReleaseName.display(release))"
        case .artisan, .certificate:
            return domain
        }
    }

    var elapsedSeconds: Int {
        Int((finishedAt ?? .now).timeIntervalSince(startedAt))
    }

    // MARK: - Streaming

    func attach(api: OrchestratorAPI = .shared) {
        let siteID = siteID
        switch kind {
        case .deploy, .rollback:
            runner.start(reconnectOnDrop: true) { api.deployStream(siteID: siteID) }
        case .artisan:
            runner.start(reconnectOnDrop: false) { api.artisanStream(siteID: siteID) }
        case .certificate:
            runner.start(reconnectOnDrop: false) { api.sslStream(siteID: siteID) }
        }
    }

    /// Closing a panel only detaches; the deploy keeps running on the server.
    func detach() {
        runner.stop()
    }

    func markFinished() {
        if finishedAt == nil { finishedAt = .now }
    }
}

/// Release directories are named `yyyyMMddHHmmss`.
enum ReleaseName {
    static func date(_ name: String) -> Date? {
        guard name.count == 14 else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter.date(from: name)
    }

    /// "release 24 Nov, 18:02", or the raw name.
    static func display(_ name: String) -> String {
        guard let date = date(name) else { return "release \(name)" }
        return "release " + date.formatted(.dateTime.day().month(.abbreviated).hour().minute())
    }
}
