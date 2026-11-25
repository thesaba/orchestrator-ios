import UserNotifications

/// Notification categories and their action buttons.
///
/// Actions here only open things or change local state (mute, snooze). Actions that change
/// production (Retry, Renew now) arrive with the confirmation flow and are not registered yet.
enum NotificationKind: String, CaseIterable {
    case deployFinished = "deploy.finished"
    case deployFailed = "deploy.failed"
    case serverAlert = "server.alert"
    case certificateExpiring = "certificate.expiring"

    enum Action: String {
        case openLog = "action.openLog"
        case openServer = "action.openServer"
        case muteHour = "action.muteHour"
        case remindTomorrow = "action.remindTomorrow"
    }

    enum UserInfoKey {
        static let siteID = "siteID"
        static let serverID = "serverID"
    }

    var category: UNNotificationCategory {
        let actions: [UNNotificationAction]
        switch self {
        case .deployFinished:
            actions = []
        case .deployFailed:
            actions = [UNNotificationAction(identifier: Action.openLog.rawValue, title: "Open log", options: [.foreground])]
        case .serverAlert:
            actions = [
                UNNotificationAction(identifier: Action.openServer.rawValue, title: "Open server", options: [.foreground]),
                UNNotificationAction(identifier: Action.muteHour.rawValue, title: "Mute for 1 hour", options: [])
            ]
        case .certificateExpiring:
            actions = [UNNotificationAction(identifier: Action.remindTomorrow.rawValue, title: "Remind tomorrow", options: [])]
        }
        return UNNotificationCategory(identifier: rawValue, actions: actions, intentIdentifiers: [], options: [])
    }
}
