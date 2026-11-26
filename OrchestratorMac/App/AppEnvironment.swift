import AppIntents
import AppKit
import Observation
import OrchestratorKit

/// Owns the app's long-lived objects and wires them together.
@MainActor
final class AppEnvironment {
    /// The running app's environment, for App Intents (which the system instantiates itself).
    private(set) static weak var current: AppEnvironment?

    let settings = AppSettings()
    let session = Session()
    let connectivity = ConnectivityMonitor()
    let store: MonitorStore
    let scheduler: RefreshScheduler
    let notifications: NotificationCoordinator
    let windows: WindowCoordinator
    let api = OrchestratorAPI.shared
    private(set) lazy var executor = CommandExecutor(environment: self)
    private(set) lazy var logs = LogCoordinator(environment: self)
    let artisanCatalog = ArtisanCatalog()
    /// The password + 2FA session for the terminal, scripts and commands (memory only).
    let admin = AdminAccess()
    private(set) var statusItem: StatusItemController?

    private var sessionObservation: ObservationLoop?
    private var lastSiteListForShortcuts: Date?

    init() {
        store = MonitorStore(settings: settings)
        defer { Self.current = self }
        scheduler = RefreshScheduler(store: store, settings: settings, connectivity: connectivity)
        notifications = NotificationCoordinator(settings: settings)
        windows = WindowCoordinator()
        windows.environment = self
        notifications.router = self
        notifications.requestSiteList = { [weak scheduler] in scheduler?.requestSiteList() }
        store.onRefresh = { [weak self] in
            guard let self else { return }
            self.notifications.process(self.store)
            // Lets Shortcuts and Spotlight offer the current sites in "Deploy <site>".
            if self.store.siteListUpdated != self.lastSiteListForShortcuts {
                self.lastSiteListForShortcuts = self.store.siteListUpdated
                OrchestratorShortcuts.updateAppShortcutParameters()
                // The Artisan allow-list for the right-click menus (one GET, once).
                self.artisanCatalog.loadIfNeeded(siteID: self.store.siteListings?.first?.id, api: self.api)
            }
        }
    }


    func start() {
        connectivity.start()
        statusItem = StatusItemController(environment: self)
        notifications.start()

        sessionObservation = ObservationLoop { [weak self] in
            _ = self?.session.phase
        } onChange: { [weak self] in
            self?.sessionPhaseChanged()
        }

        Task {
            await session.bootstrap()
            sessionPhaseChanged()
            // The main window opens at launch; without a token the sign-in window comes first.
            windows.showMain()
            if session.phase == .signedOut {
                windows.showSignIn()
            }
        }
    }

    func stop() {
        scheduler.stop()
        connectivity.stop()
    }

    // MARK: - Session

    private func sessionPhaseChanged() {
        switch session.phase {
        case .signedIn:
            windows.closeSignIn()
            notifications.requestAuthorization()
            scheduler.start()
        case .signedOut:
            scheduler.stop()
            store.reset()
            admin.signOut()
            windows.main?.model.data.reset()
        case .launching:
            break
        }
    }

    // MARK: - Deep links

    /// Opens what an `orchestrator://` link points at. Never runs a write.
    func open(_ link: DeepLink) {
        guard session.phase != .signedOut else {
            windows.showSignIn()
            return
        }
        switch link {
        case .popover(let segment):
            let target: PopoverSegment
            switch segment {
            case .overview: target = .overview
            case .servers:  target = .servers
            case .sites:    target = .sites
            case .alerts:   target = .alerts
            }
            statusItem?.showPopover(segment: target)
        case .settings:
            windows.showSettings()
        case .deployLog(let siteID):
            logs.showWindow(siteID: siteID, domain: executor.domain(of: siteID))
        case .siteLogs(let siteID):
            windows.showSiteLogs(siteID: siteID, domain: executor.domain(of: siteID))
        case .site(let siteID):
            windows.showMain()
            windows.main?.model.openSite(siteID)
        case .siteTab(let siteID, let tab):
            windows.showMain()
            windows.main?.model.openSite(siteID, tab: SiteTab(rawValue: tab) ?? .overview)
        case .server(let serverID):
            windows.showMain()
            windows.main?.model.openServer(serverID)
        }
    }

    func signOut() {
        session.signOut()
        notifications.resetLedger()
    }
}

// MARK: - Routing from notifications and rows

extension AppEnvironment: NotificationRouter {
    func openPopover(segment: PopoverSegment) {
        statusItem?.showPopover(segment: segment)
    }

    func openWebPanel(_ destination: WebPanel.Destination) {
        WebPanel.open(destination)
    }

    func openDeployLog(siteID: Int, explain: Bool) {
        logs.showWindow(siteID: siteID, domain: executor.domain(of: siteID))
        if explain {
            // Runs once the history has loaded, so the newest deployment is the one explained.
            logs.windowModel(siteID: siteID)?.explainAfterLoad = true
        }
    }

    func retryDeploy(siteID: Int) {
        Task { await executor.retryDeploy(siteID: siteID) }
    }

    func renewCertificate(siteID: Int) {
        Task { await executor.renewCertificate(siteID: siteID) }
    }
}
