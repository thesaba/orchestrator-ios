import AppKit
import Observation
import OrchestratorKit

/// Owns the app's long-lived objects and wires them together.
@MainActor
final class AppEnvironment {
    let settings = AppSettings()
    let session = Session()
    let connectivity = ConnectivityMonitor()
    let store: MonitorStore
    let scheduler: RefreshScheduler
    let notifications: NotificationCoordinator
    let windows: WindowCoordinator
    private(set) var statusItem: StatusItemController?

    private var sessionObservation: ObservationLoop?

    init() {
        store = MonitorStore(settings: settings)
        scheduler = RefreshScheduler(store: store, settings: settings, connectivity: connectivity)
        notifications = NotificationCoordinator(settings: settings)
        windows = WindowCoordinator()
        windows.environment = self
        notifications.router = self
        notifications.requestSiteList = { [weak scheduler] in scheduler?.requestSiteList() }
        store.onRefresh = { [weak self] in
            guard let self else { return }
            self.notifications.process(self.store)
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
            // No Dock icon: without a token, open the sign-in window so launch is not silent.
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
        case .launching:
            break
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
}
