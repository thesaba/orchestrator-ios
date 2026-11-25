import Foundation
import Observation
import OrchestratorKit

/// User preferences, kept in the App Group defaults so the widget extension can read them.
@MainActor
@Observable
final class AppSettings {
    /// Allowed refresh intervals, in seconds.
    static let fastChoices = [10, 15, 30, 60]
    static let backgroundChoices = [60, 120, 300, 600]
    static let siteListChoices = [120, 300, 600, 1_800]

    /// Certificates with this many days left or fewer raise an alert.
    static let sslWarningDays = 14

    /// While the popover is open.
    var fastRefreshSeconds: Int { didSet { store(fastRefreshSeconds, .fast) } }
    /// While the popover is closed.
    var backgroundRefreshSeconds: Int { didSet { store(backgroundRefreshSeconds, .background) } }
    /// `GET /sites` carries every site's last deploy log, so it has its own, slower interval.
    var siteListRefreshSeconds: Int { didSet { store(siteListRefreshSeconds, .siteList) } }

    var notifyDeploys: Bool { didSet { store(notifyDeploys, .notifyDeploys) } }
    var notifyServerAlerts: Bool { didSet { store(notifyServerAlerts, .notifyServerAlerts) } }
    var notifyCertificates: Bool { didSet { store(notifyCertificates, .notifyCertificates) } }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = SharedContainer.defaults) {
        self.defaults = defaults
        fastRefreshSeconds = Self.read(defaults, .fast, default: 15)
        backgroundRefreshSeconds = Self.read(defaults, .background, default: 120)
        siteListRefreshSeconds = Self.read(defaults, .siteList, default: 300)
        notifyDeploys = Self.read(defaults, .notifyDeploys, default: true)
        notifyServerAlerts = Self.read(defaults, .notifyServerAlerts, default: true)
        notifyCertificates = Self.read(defaults, .notifyCertificates, default: true)
    }

    private enum Key: String {
        case fast = "settings.refresh.fast"
        case background = "settings.refresh.background"
        case siteList = "settings.refresh.siteList"
        case notifyDeploys = "settings.notify.deploys"
        case notifyServerAlerts = "settings.notify.serverAlerts"
        case notifyCertificates = "settings.notify.certificates"
    }

    private func store(_ value: some Any, _ key: Key) {
        defaults.set(value, forKey: key.rawValue)
    }

    private static func read<T>(_ defaults: UserDefaults, _ key: Key, default value: T) -> T {
        defaults.object(forKey: key.rawValue) as? T ?? value
    }
}
