import AppKit
import Observation
import OrchestratorKit

/// The full log window of one site: the live session when there is one, otherwise a past
/// deploy picked from "Previous deploys". History comes from `GET /sites/:id` (read-only).
@MainActor
@Observable
final class DeployLogWindowModel {
    enum Explanation: Equatable {
        case idle, loading, loaded(String), failed(String)
    }

    let siteID: Int
    let domain: String

    private(set) var deployments: [DeploymentRecord] = []
    private(set) var isLoadingHistory = false
    private(set) var historyError: String?
    /// nil shows the live session.
    private(set) var selectedDeploymentID: Int?
    var search = ""
    var errorsOnly = false
    var scrollTarget: Int?
    private(set) var explanation: Explanation = .idle
    var isShowingExplanation = false
    /// Set by a notification's Explain button; consumed by `load()`.
    @ObservationIgnored var explainAfterLoad = false

    @ObservationIgnored private unowned let environment: AppEnvironment
    @ObservationIgnored private let historyBuffer = LogBuffer()
    @ObservationIgnored private var summaries: [Int: DeployLogSummary] = [:]

    init(siteID: Int, domain: String, environment: AppEnvironment) {
        self.siteID = siteID
        self.domain = domain
        self.environment = environment
        historyBuffer.limit = 20_000
    }

    var live: LogSession? { environment.logs.session(for: siteID) }

    var isShowingLive: Bool { selectedDeploymentID == nil && live != nil }

    var selectedDeployment: DeploymentRecord? {
        guard let selectedDeploymentID else { return nil }
        return deployments.first { $0.id == selectedDeploymentID }
    }

    // MARK: - Content

    /// Every line of what is shown, before search and filter.
    var allLines: [LogLine] {
        if isShowingLive, let live { return live.lines }
        _ = selectedDeploymentID
        return historyLines
    }

    private(set) var historyLines: [LogLine] = []

    var visibleLines: [LogLine] {
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        return allLines.filter { line in
            if errorsOnly && LogLineStyle.classify(LogLineStyle.split(line.text).text) != .error { return false }
            if !needle.isEmpty && !line.text.lowercased().contains(needle) { return false }
            return true
        }
    }

    var summary: DeployLogSummary {
        if isShowingLive, let live { return live.summary }
        guard let deployment = selectedDeployment else { return DeployLogSummary() }
        return summary(for: deployment)
    }

    /// "running", "success", "failed".
    var status: String {
        if isShowingLive, let live {
            switch live.state {
            case .succeeded:            return "success"
            case .failed, .cancelled:   return "failed"
            case .notRunning:           return selectedDeployment?.status ?? "unknown"
            default:                    return "running"
            }
        }
        return selectedDeployment?.status ?? "unknown"
    }

    var deploymentID: Int? {
        isShowingLive ? (live?.deploymentID ?? deployments.first?.id) : selectedDeploymentID
    }

    var branch: String? { isShowingLive ? live?.branch : selectedDeployment?.branch }

    var shortCommit: String? {
        if isShowingLive { return live?.commit ?? summary.commit.map { String($0.prefix(7)) } }
        return selectedDeployment?.shortCommit
    }

    var startedAt: Date? { isShowingLive ? live?.startedAt : selectedDeployment?.createdAt }

    var durationSeconds: Int? {
        if isShowingLive, let live { return live.elapsedSeconds }
        return summary.durationSeconds
    }

    var isRollback: Bool {
        if isShowingLive, let live, case .rollback = live.kind { return true }
        return selectedDeployment?.branch == "rollback"
    }

    /// The error lines, for "Copy error".
    var errorText: String {
        allLines.map(\.text).filter { LogLineStyle.classify(LogLineStyle.split($0).text) == .error }.joined(separator: "\n")
    }

    func summary(for deployment: DeploymentRecord) -> DeployLogSummary {
        if let cached = summaries[deployment.id] { return cached }
        let parsed = DeployLogParser.parse(deployment.log ?? "", status: deployment.status)
        summaries[deployment.id] = parsed
        return parsed
    }

    /// Line id of a step header, for clicking a step in the sidebar.
    func lineID(for step: DeployStep) -> Int? {
        allLines.first { $0.text.contains("[\(step.id)/") }?.id
    }

    // MARK: - Loading

    func load() async {
        await loadHistory()
        if live == nil, selectedDeploymentID == nil, let first = deployments.first {
            select(first)
        }
        if explainAfterLoad {
            explainAfterLoad = false
            explain()
        }
    }

    func reloadHistory() {
        Task { await loadHistory() }
    }

    private func loadHistory() async {
        isLoadingHistory = true
        defer { isLoadingHistory = false }
        do {
            let listing = try await environment.api.siteListing(id: siteID)
            deployments = listing.deployments
            summaries = [:]
            historyError = nil
            if let selected = selectedDeployment { show(selected) }
        } catch {
            historyError = APIError.wrap(error).errorDescription
        }
    }

    func select(_ deployment: DeploymentRecord) {
        selectedDeploymentID = deployment.id
        explanation = .idle
        show(deployment)
    }

    func selectLive() {
        selectedDeploymentID = nil
        explanation = .idle
    }

    private func show(_ deployment: DeploymentRecord) {
        historyBuffer.replace(with: deployment.log ?? "This deployment has no stored log.")
        historyLines = historyBuffer.lines
    }

    // MARK: - Actions

    func copyLog() {
        copy(allLines.map(\.text).joined(separator: "\n"))
    }

    func copyError() {
        copy(errorText.isEmpty ? allLines.suffix(30).map(\.text).joined(separator: "\n") : errorText)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func retry() {
        let executor = environment.executor
        let siteID = siteID
        Task { await executor.retryDeploy(siteID: siteID) }
    }

    /// The stored diagnosis first (GET); if there is none, asks the AI (POST, which changes
    /// nothing on the site). `force` asks again.
    func explain(force: Bool = false) {
        guard let deploymentID else {
            explanation = .failed("This deploy has no id yet. Try again once it has finished.")
            isShowingExplanation = true
            return
        }
        explanation = .loading
        isShowingExplanation = true
        let api = environment.api
        Task {
            do {
                if !force, let stored = try? await api.storedDeployExplanation(deploymentID: deploymentID).explanation {
                    explanation = .loaded(stored)
                    return
                }
                let fresh = try await api.explainDeployment(deploymentID: deploymentID, force: force)
                explanation = fresh.explanation.map(Explanation.loaded) ?? .failed("The AI returned no explanation.")
            } catch {
                explanation = .failed(APIError.wrap(error).errorDescription ?? "The request failed.")
            }
        }
    }
}
