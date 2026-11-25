import Foundation
import OrchestratorKit
import UserNotifications

/// Where a notification click leads.
@MainActor
protocol NotificationRouter: AnyObject {
    func openPopover(segment: PopoverSegment)
    func openWebPanel(_ destination: WebPanel.Destination)
    func openDeployLog(siteID: Int, explain: Bool)
    /// Opens the confirmation; nothing runs until the user confirms.
    func retryDeploy(siteID: Int)
    /// Opens the confirmation; nothing runs until the user confirms.
    func renewCertificate(siteID: Int)
}

/// Turns changes between refreshes into system notifications: deploy results (from the
/// panel's notification feed), new fleet alerts, and certificates close to expiry.
@MainActor
final class NotificationCoordinator: NSObject {
    weak var router: NotificationRouter?

    private let settings: AppSettings
    private let defaults: UserDefaults
    private let center = UNUserNotificationCenter.current()
    private var ledger: NotificationLedger
    /// Deploy results waiting for the site list to show how the deploy ended.
    private var pendingDeploys: [AppNotification] = []
    /// Asks the store for a fresh site list when a deploy result arrives.
    var requestSiteList: (() -> Void)?

    private static let pendingDeployTimeout: TimeInterval = 120
    private static let maxPerKindPerRefresh = 5

    init(settings: AppSettings, defaults: UserDefaults = SharedContainer.defaults) {
        self.settings = settings
        self.defaults = defaults
        self.ledger = NotificationLedger.load(from: defaults)
        super.init()
    }

    func start() {
        center.delegate = self
        center.setNotificationCategories(Set(NotificationKind.allCases.map(\.category)))
    }

    func requestAuthorization() {
        Task {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
    }

    /// Forget everything announced, e.g. after signing out or switching accounts.
    func resetLedger() {
        ledger = NotificationLedger()
        pendingDeploys = []
        NotificationLedger.reset(in: defaults)
    }

    // MARK: - Processing a refresh

    func process(_ store: MonitorStore) {
        ledger.pruneExpired()
        processDeploys(store)
        processAlerts(store)
        processCertificates(store)
        ledger.save(to: defaults)
    }

    private func processDeploys(_ store: MonitorStore) {
        let deployEvents = store.notifications.filter { ($0.type ?? "") == "deploy" }
        guard let newest = deployEvents.map(\.id).max() else { return }

        guard let lastID = ledger.lastNotificationID else {
            ledger.lastNotificationID = newest
            return
        }
        let fresh = deployEvents.filter { $0.id > lastID }.sorted { $0.id < $1.id }
        ledger.lastNotificationID = max(lastID, newest)
        if !fresh.isEmpty, settings.notifyDeploys {
            pendingDeploys.append(contentsOf: fresh.suffix(Self.maxPerKindPerRefresh))
            requestSiteList?()
        }

        var waiting: [AppNotification] = []
        for event in pendingDeploys {
            let site = event.siteId.flatMap(store.site(id:))
            let listedAfterEvent = (store.siteListUpdated ?? .distantPast) >= (event.createdAt ?? .distantPast)
            let settled = site.map { $0.lastDeployStatus != "running" } ?? true
            let timedOut = Date.now.timeIntervalSince(event.createdAt ?? .now) > Self.pendingDeployTimeout
            if (listedAfterEvent && settled) || timedOut {
                post(deploy: event, site: listedAfterEvent ? site : nil)
            } else {
                waiting.append(event)
            }
        }
        pendingDeploys = waiting
    }

    private func processAlerts(_ store: MonitorStore) {
        let open = store.alerts.filter(\.isActive)
        // Every open alert counts as handled after this pass; resolved ones drop out, so an
        // alert that fires again later gets a new event id and a new notification.
        defer { ledger.announcedAlertIDs = Set(open.map(\.id)) }

        guard ledger.hasAlertBaseline else {
            ledger.hasAlertBaseline = true
            ledger.announcedAlertIDs = Set(open.map(\.id))
            return
        }
        let fresh = open.filter { !ledger.announcedAlertIDs.contains($0.id) }
        guard settings.notifyServerAlerts else { return }
        for alert in fresh.prefix(Self.maxPerKindPerRefresh) where !ledger.isMuted(server: alert.serverId) {
            post(alert: alert, server: store.server(id: alert.serverId)?.server)
        }
    }

    private func processCertificates(_ store: MonitorStore) {
        guard settings.notifyCertificates else { return }
        let today = Self.dayString(.now)
        for item in store.overview.attention {
            guard case .certificate(let siteID) = item.subject,
                  ledger.certificateAnnouncedOn[siteID] != today,
                  !ledger.isSnoozed(certificate: siteID) else { continue }
            ledger.certificateAnnouncedOn[siteID] = today
            post(certificate: item, siteID: siteID)
        }
    }

    // MARK: - Content

    private func post(deploy event: AppNotification, site: SiteStatus?) {
        let failed = (event.level ?? "") != "success"
        let content = UNMutableNotificationContent()
        content.title = failed ? "Deploy failed" : "Deploy finished"
        let domain = event.domain ?? site?.domain ?? "Site"

        if failed, let summary = site?.deploy {
            var body = domain
            if let step = summary.failedStep { body += " stopped at \(step.title)." } else { body += " failed." }
            if summary.rolledBack {
                body += " The previous release was restored."
            } else if summary.reachedActivation {
                body += " The new release went live before the failure."
            } else {
                body += " The previous release is still live."
            }
            content.body = body
        } else {
            var parts = [domain]
            if let branch = site?.branch { parts.append(branch) }
            if let commit = site?.shortCommit { parts.append(commit) }
            if let seconds = site?.deploy?.durationSeconds { parts.append(Durations.elapsed(seconds)) }
            if parts.count == 1, let body = event.body { parts.append(body) }
            content.body = parts.joined(separator: " · ")
        }

        content.categoryIdentifier = (failed ? NotificationKind.deployFailed : .deployFinished).rawValue
        if let siteID = event.siteId { content.userInfo = [NotificationKind.UserInfoKey.siteID: siteID] }
        content.threadIdentifier = "deploys"
        content.sound = failed ? .default : nil
        add(content, id: "deploy-\(event.id)")
    }

    private func post(alert: FleetAlertEvent, server: FleetServer?) {
        let content = UNMutableNotificationContent()
        content.title = FleetAlertKind.headline(kind: alert.kind, value: alert.value, message: alert.message)
        var parts = [alert.serverName]
        if let location = server?.location { parts.append(location) }
        if let message = alert.message, !message.isEmpty { parts.append(message) }
        content.body = parts.joined(separator: " · ")
        content.categoryIdentifier = NotificationKind.serverAlert.rawValue
        content.userInfo = [NotificationKind.UserInfoKey.serverID: alert.serverId]
        content.threadIdentifier = "server-\(alert.serverId)"
        content.sound = .default
        add(content, id: "alert-\(alert.id)")
    }

    private func post(certificate item: AttentionItem, siteID: Int) {
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = item.source
        content.categoryIdentifier = NotificationKind.certificateExpiring.rawValue
        content.userInfo = [NotificationKind.UserInfoKey.siteID: siteID]
        content.threadIdentifier = "certificates"
        add(content, id: "ssl-\(siteID)-\(Self.dayString(.now))")
    }

    /// A plain confirmation of something the user just did ("Maintenance mode on").
    func postInfo(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.threadIdentifier = "actions"
        add(content, id: "info-\(UUID().uuidString)")
    }

    private func add(_ content: UNNotificationContent, id: String) {
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    // MARK: - Responses

    fileprivate func handle(category: String, action: String, siteID: Int?, serverID: Int?) {
        guard let kind = NotificationKind(rawValue: category) else { return }
        switch (kind, NotificationKind.Action(rawValue: action)) {
        case (.serverAlert, .muteHour):
            if let serverID {
                ledger.serverMutedUntil[serverID] = .now.addingTimeInterval(3_600)
                ledger.save(to: defaults)
            }
        case (.serverAlert, .openServer):
            if let serverID { router?.openWebPanel(.server(id: serverID)) }
        case (.serverAlert, _):
            router?.openPopover(segment: .alerts)
        case (.certificateExpiring, .remindTomorrow):
            if let siteID {
                ledger.certificateSnoozedUntil[siteID] = Self.tomorrowMorning()
                ledger.certificateAnnouncedOn[siteID] = nil
                ledger.save(to: defaults)
            }
        case (.certificateExpiring, .renewNow):
            if let siteID { router?.renewCertificate(siteID: siteID) }
        case (.certificateExpiring, _):
            router?.openPopover(segment: .alerts)
        case (.deployFailed, .retry):
            if let siteID { router?.retryDeploy(siteID: siteID) }
        case (.deployFailed, .explain):
            if let siteID { router?.openDeployLog(siteID: siteID, explain: true) }
        case (.deployFinished, _), (.deployFailed, _):
            if let siteID { router?.openDeployLog(siteID: siteID, explain: false) } else { router?.openPopover(segment: .sites) }
        }
    }

    // MARK: - Dates

    private static func dayString(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private static func tomorrowMorning() -> Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now)) ?? .now
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }
}

extension NotificationCoordinator: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let content = response.notification.request.content
        let category = content.categoryIdentifier
        let action = response.actionIdentifier
        let siteID = content.userInfo[NotificationKind.UserInfoKey.siteID] as? Int
        let serverID = content.userInfo[NotificationKind.UserInfoKey.serverID] as? Int
        await MainActor.run {
            self.handle(category: category, action: action, siteID: siteID, serverID: serverID)
        }
    }
}
