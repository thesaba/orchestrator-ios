import AppKit
import OrchestratorKit

/// Decides when `MonitorStore` refreshes.
///
/// - Fast interval while the popover or the main window is open, slow interval otherwise.
/// - The heavy site list on its own interval; on opening the popover when it is older than a
///   minute; every 30 s while a deploy runs and the popover is open.
/// - Paused while the Mac sleeps or is offline; refreshes right after wake and reconnect.
@MainActor
@Observable
final class RefreshScheduler {
    /// Set from the menu bar menu: no polling at all until resumed (not kept across launches).
    private(set) var isPaused = false

    @ObservationIgnored var isPopoverOpen = false {
        didSet {
            guard isPopoverOpen != oldValue else { return }
            reschedule(refreshNow: isPopoverOpen)
        }
    }

    /// The main window is on screen (not minimised or hidden): polls as fast as the popover.
    @ObservationIgnored var isMainWindowVisible = false {
        didSet {
            guard isMainWindowVisible != oldValue else { return }
            reschedule(refreshNow: isMainWindowVisible)
        }
    }

    /// Someone is looking at the data.
    private var isForeground: Bool { isPopoverOpen || isMainWindowVisible }

    @ObservationIgnored private let store: MonitorStore
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let connectivity: ConnectivityMonitor
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var isAsleep = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var observations: [ObservationLoop] = []

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

    func pause() {
        isPaused = true
        loop?.cancel()
        loop = nil
    }

    func resume() {
        guard isPaused else { return }
        isPaused = false
        reschedule(refreshNow: true, forceSiteList: true)
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

    private var canRefresh: Bool { isRunning && !isPaused && !isAsleep && connectivity.isOnline }

    private var interval: TimeInterval {
        TimeInterval(isForeground ? settings.fastRefreshSeconds : settings.backgroundRefreshSeconds)
    }

    private func reschedule(refreshNow: Bool, forceSiteList: Bool = false, delay: TimeInterval = 0) {
        loop?.cancel()
        guard isRunning, !isPaused else { return }
        loop = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            var shouldRefresh = refreshNow
            var forceSites = forceSiteList
            while !Task.isCancelled {
                guard let self else { return }
                if shouldRefresh, self.canRefresh {
                    // In its own task: rescheduling cancels this loop, and a refresh cancelled
                    // halfway would report every source as failed and show an empty fleet.
                    let store = self.store
                    let includeSiteList = forceSites || self.siteListIsDue
                    await Task { await store.refresh(includeSiteList: includeSiteList) }.value
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
        if isForeground, store.overview.isDeploying { return age >= Self.siteListWhileDeploying }
        if isForeground { return age >= Self.siteListOnOpenAge }
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
