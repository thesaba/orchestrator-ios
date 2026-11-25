import AppKit
import OrchestratorKit

/// Owns live log sessions and the panels and windows that show them, one per site.
///
/// Streams are attached only on a user action: running a command, "Show log", opening a
/// log from the palette or a notification. Closing a panel detaches; the server keeps going.
@MainActor
final class LogCoordinator {
    private unowned let environment: AppEnvironment
    private(set) var sessions: [Int: LogSession] = [:]
    private var compactPanels: [Int: CompactLogPanelController] = [:]
    private var windows: [Int: DeployLogWindowController] = [:]
    private var finishObservers: [Int: ObservationLoop] = [:]

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    // MARK: - Sessions

    /// Attaches a new session for its site (replacing an older one) and shows it.
    func start(_ session: LogSession, showFullLog: Bool) {
        sessions[session.siteID]?.detach()
        // A panel shows one session; a new deploy on the same site gets a fresh panel.
        compactPanels[session.siteID]?.close()
        compactPanels[session.siteID] = nil
        sessions[session.siteID] = session
        session.attach(api: environment.api)
        observeFinish(session)
        if showFullLog {
            showWindow(siteID: session.siteID, domain: session.domain)
        } else {
            showCompact(siteID: session.siteID)
        }
    }

    /// "Show log" on a deploying site in the popover.
    func showLiveDeploy(for site: SiteStatus) {
        if let session = sessions[site.id], session.isDeployLike, !session.isFinished {
            showCompact(siteID: site.id)
            return
        }
        let session = LogSession(siteID: site.id, domain: site.domain, kind: .deploy, branch: site.branch,
                                 commit: site.shortCommit, deploymentID: site.lastDeploymentID,
                                 startedAt: site.lastDeployAt ?? .now)
        start(session, showFullLog: false)
    }

    func session(for siteID: Int) -> LogSession? { sessions[siteID] }

    private func observeFinish(_ session: LogSession) {
        finishObservers[session.siteID] = ObservationLoop { _ = session.isFinished } onChange: { [weak self, weak session] in
            guard let self, let session, session.isFinished else { return }
            session.markFinished()
            self.finishObservers[session.siteID]?.cancel()
            self.finishObservers[session.siteID] = nil
            self.environment.scheduler.requestSiteList()
            self.windows[session.siteID]?.model.reloadHistory()
        }
    }

    // MARK: - Compact panel

    func showCompact(siteID: Int) {
        guard let session = sessions[siteID] else { return }
        if let window = windows[siteID] { window.close() }
        let controller = compactPanels[siteID] ?? CompactLogPanelController(session: session, coordinator: self,
                                                                           index: compactPanels.count)
        compactPanels[siteID] = controller
        controller.show()
    }

    func closeCompact(siteID: Int) {
        compactPanels[siteID]?.close()
        compactPanels[siteID] = nil
        releaseSessionIfUnused(siteID)
    }

    /// Compact panel → full window.
    func expand(siteID: Int) {
        guard let session = sessions[siteID] else { return }
        compactPanels[siteID]?.close()
        compactPanels[siteID] = nil
        showWindow(siteID: siteID, domain: session.domain)
    }

    // MARK: - Full window

    func showWindow(siteID: Int, domain: String) {
        let controller = windows[siteID] ?? DeployLogWindowController(
            model: DeployLogWindowModel(siteID: siteID, domain: domain, environment: environment),
            coordinator: self)
        windows[siteID] = controller
        controller.show()
    }

    /// Full window → compact panel (only while something is live).
    func shrink(siteID: Int) {
        windows[siteID]?.close()
        if sessions[siteID]?.isFinished == false {
            showCompact(siteID: siteID)
        }
    }

    func windowModel(siteID: Int) -> DeployLogWindowModel? {
        windows[siteID]?.model
    }

    func windowDidClose(siteID: Int) {
        windows[siteID] = nil
        releaseSessionIfUnused(siteID)
    }

    /// With no panel or window left, stop streaming. The deploy itself is not touched.
    private func releaseSessionIfUnused(_ siteID: Int) {
        guard compactPanels[siteID] == nil, windows[siteID] == nil, let session = sessions[siteID] else { return }
        session.detach()
        finishObservers[siteID]?.cancel()
        finishObservers[siteID] = nil
        sessions[siteID] = nil
    }
}
