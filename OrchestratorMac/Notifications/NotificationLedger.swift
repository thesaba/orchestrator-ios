import Foundation
import OrchestratorKit

/// What has already been announced, so a restart or a refresh never repeats a notification.
/// Mutes and snoozes are local to this Mac; nothing is written to the panel.
struct NotificationLedger: Codable {
    /// Highest `/notifications` id already seen. `nil` until the first refresh sets a baseline.
    var lastNotificationID: Int?
    /// Fleet alert events already announced.
    var announcedAlertIDs: Set<Int> = []
    /// Whether alerts have a baseline yet (alerts open at first launch are not announced).
    var hasAlertBaseline = false
    /// Site id → day (yyyy-MM-dd) a certificate warning was last shown.
    var certificateAnnouncedOn: [Int: String] = [:]
    /// Site id → "Remind tomorrow" snooze end.
    var certificateSnoozedUntil: [Int: Date] = [:]
    /// Server id → "Mute for 1 hour" end.
    var serverMutedUntil: [Int: Date] = [:]

    func isMuted(server id: Int, now: Date = .now) -> Bool {
        (serverMutedUntil[id] ?? .distantPast) > now
    }

    func isSnoozed(certificate siteID: Int, now: Date = .now) -> Bool {
        (certificateSnoozedUntil[siteID] ?? .distantPast) > now
    }

    mutating func pruneExpired(now: Date = .now) {
        serverMutedUntil = serverMutedUntil.filter { $0.value > now }
        certificateSnoozedUntil = certificateSnoozedUntil.filter { $0.value > now }
    }

    // MARK: - Persistence

    private static let key = "notifications.ledger"

    static func load(from defaults: UserDefaults) -> NotificationLedger {
        guard let data = defaults.data(forKey: key),
              let ledger = try? JSONDecoder().decode(NotificationLedger.self, from: data) else {
            return NotificationLedger()
        }
        return ledger
    }

    func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.key)
        }
    }

    static func reset(in defaults: UserDefaults) {
        defaults.removeObject(forKey: key)
    }
}
