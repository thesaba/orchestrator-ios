import UserNotifications

/// Notification categories and their action buttons.
///
/// Retry and Renew now change production: they only open the app's confirmation, and nothing
/// runs until it is confirmed. Every other action opens something or changes local state.
enum NotificationKind: String, CaseIterable {
    case deployFinished = "deploy.finished"
    case deployFailed = "deploy.failed"
    case serverAlert = "server.alert"
    case certificateExpiring = "certificate.expiring"

    enum Action: String {
        case explain = "action.explain"
        case retry = "action.retry"
        case renewNow = "action.renewNow"
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
            actions = [
                UNNotificationAction(identifier: Action.explain.rawValue, title: "Explain", options: [.foreground]),
                UNNotificationAction(identifier: Action.openLog.rawValue, title: "Open log", options: [.foreground]),
                UNNotificationAction(identifier: Action.retry.rawValue, title: "Retry…", options: [.foreground])
            ]
        case .serverAlert:
            actions = [
                UNNotificationAction(identifier: Action.openServer.rawValue, title: "Open server", options: [.foreground]),
                UNNotificationAction(identifier: Action.muteHour.rawValue, title: "Mute for 1 hour", options: [])
            ]
        case .certificateExpiring:
            actions = [
                UNNotificationAction(identifier: Action.renewNow.rawValue, title: "Renew now…", options: [.foreground]),
                UNNotificationAction(identifier: Action.remindTomorrow.rawValue, title: "Remind tomorrow", options: [])
            ]
        }
        return UNNotificationCategory(identifier: rawValue, actions: actions, intentIdentifiers: [], options: [])
    }
}
