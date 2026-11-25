import AppKit
import OrchestratorKit

/// Decides when `MonitorStore` refreshes.
///
/// - Fast interval while the popover is open, slow interval otherwise.
/// - The heavy site list on its own interval; on opening the popover when it is older than a
///   minute; every 30 s while a deploy runs and the popover is open.
/// - Paused while the Mac sleeps or is offline; refreshes right after wake and reconnect.
@MainActor
final class RefreshScheduler {
    var isPopoverOpen = false {
        didSet {
            guard isPopoverOpen != oldValue else { return }
            reschedule(refreshNow: isPopoverOpen)
        }
    }

    private let store: MonitorStore
    private let settings: AppSettings
    private let connectivity: ConnectivityMonitor
    private var loop: Task<Void, Never>?
    private var isRunning = false
    private var isAsleep = false
    private var observers: [NSObjectProtocol] = []
    private var observations: [ObservationLoop] = []

    private static let siteListOnOpenAge: TimeInterval = 60
    private static let siteListWhileDeploying: TimeInterval = 30

    init(store: MonitorStore, settings: AppSettings, connectivity: ConnectivityMonitor) {
        self.store = store
        self.settings = settings
        self.connectivity = connectivity
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        observeSystem()
        reschedule(refreshNow: true, forceSiteList: true)
    }

    func stop() {
        isRunning = false
        loop?.cancel()
        loop = nil
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach(center.removeObserver)
        observers.removeAll()
        observations.forEach { $0.cancel() }
        observations.removeAll()
    }

    /// Manual refresh from the popover's Refresh button.
    func refreshNow() {
        reschedule(refreshNow: true, forceSiteList: true)
    }

    /// A deploy just finished somewhere: fetch the site list shortly so its result can be read.
    /// Delayed because this is called from inside a refresh, which must finish first.
    func requestSiteList() {
        reschedule(refreshNow: true, forceSiteList: true, delay: 3)
    }

    // MARK: - Loop

    private var canRefresh: Bool { isRunning && !isAsleep && connectivity.isOnline }

    private var interval: TimeInterval {
        TimeInterval(isPopoverOpen ? settings.fastRefreshSeconds : settings.backgroundRefreshSeconds)
    }

    private func reschedule(refreshNow: Bool, forceSiteList: Bool = false, delay: TimeInterval = 0) {
        loop?.cancel()
        guard isRunning else { return }
        loop = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            var shouldRefresh = refreshNow
            var forceSites = forceSiteList
            while !Task.isCancelled {
                guard let self else { return }
                if shouldRefresh, self.canRefresh {
                    await self.store.refresh(includeSiteList: forceSites || self.siteListIsDue)
                }
                shouldRefresh = true
                forceSites = false
                try? await Task.sleep(for: .seconds(self.interval))
            }
        }
    }

    private var siteListIsDue: Bool {
        guard let updated = store.siteListUpdated else { return true }
        let age = Date.now.timeIntervalSince(updated)
        if isPopoverOpen, store.overview.isDeploying { return age >= Self.siteListWhileDeploying }
        if isPopoverOpen { return age >= Self.siteListOnOpenAge }
        return age >= TimeInterval(settings.siteListRefreshSeconds)
    }

    // MARK: - System events

    private func observeSystem() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.isAsleep = true }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isAsleep = false
                self.reschedule(refreshNow: true)
            }
        })
        observations.append(ObservationLoop { [weak self] in
            _ = self?.connectivity.isOnline
        } onChange: { [weak self] in
            guard let self, self.connectivity.isOnline else { return }
            self.reschedule(refreshNow: true)
        })
        // Interval settings take effect without waiting for the current sleep to end.
        observations.append(ObservationLoop { [weak self] in
            _ = self?.settings.fastRefreshSeconds
            _ = self?.settings.backgroundRefreshSeconds
        } onChange: { [weak self] in
            self?.reschedule(refreshNow: false)
        })
    }
}
