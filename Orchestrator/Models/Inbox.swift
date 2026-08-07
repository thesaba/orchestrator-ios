import Foundation

/// `GET /api/notifications`
struct NotificationsResponse: Decodable, Sendable {
    var notifications: [AppNotification]
    var unread: Int?
}

struct AppNotification: Identifiable, Decodable, Sendable, Hashable {
    var id: Int
    var type: String?
    var level: String?
    var title: String
    var body: String?
    /// JSON encoded inside a string, e.g. `{"siteId":6,"domain":"netflow.ge"}`.
    var meta: String?
    var read: Bool
    var createdAt: Date?

    var tone: StatusTone { StatusTone(status: level) }

    var symbol: String {
        switch (type ?? "").lowercased() {
        case "deploy":  return "arrow.up.circle"
        case "ssl":     return "lock.shield"
        case "uptime":  return "waveform.path.ecg"
        case "billing": return "creditcard"
        case "error":   return "exclamationmark.triangle"
        default:        return "bell"
        }
    }

    private var metaObject: JSONValue? { EmbeddedJSON.decode(JSONValue.self, from: meta) }
    var siteId: Int? { metaObject?["siteId"]?.intValue }
    var domain: String? { metaObject?["domain"]?.stringValue }
}

/// `GET /api/log-errors` — the panel's mini-Sentry.
struct LogErrorsResponse: Decodable, Sendable {
    var errors: [LogError]
    var unresolved: Int?
}

struct LogError: Identifiable, Decodable, Sendable, Hashable {
    struct SiteRef: Decodable, Sendable, Hashable {
        var domain: String?
    }

    var id: Int
    var siteId: Int?
    var level: String?
    var exceptionClass: String?
    var message: String?
    var count: Int?
    var firstSeenAt: Date?
    var lastSeenAt: Date?
    var resolved: Bool
    var ignored: Bool
    var site: SiteRef?

    var tone: StatusTone {
        if resolved || ignored { return .neutral }
        return StatusTone(status: level)
    }

    var headline: String { exceptionClass ?? level?.capitalized ?? "Error" }
}

/// `GET /api/alerts`
struct AlertRulesResponse: Decodable, Sendable {
    var rules: [AlertRule]
}

struct AlertRule: Identifiable, Decodable, Sendable, Hashable {
    var id: Int
    var metric: String
    var comparison: String
    var threshold: Int
    var enabled: Bool
    var cooldownMins: Int?
    var lastTriggeredAt: Date?
    var createdAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id, metric, threshold, enabled, cooldownMins, lastTriggeredAt, createdAt
        case comparison = "operator"
    }

    var summary: String { "\(metric) \(comparison) \(threshold)" }
}

/// `GET /api/billing/overview` — every amount is integer minor units (თეთრი).
struct BillingOverview: Decodable, Sendable, Hashable {
    struct Aging: Decodable, Sendable, Hashable {
        var current: Int?
        var d1_30: Int?
        var d31_60: Int?
        var d61_plus: Int?
        var total: Int?
    }

    var mode: String?
    var currency: String?
    var clients: Int?
    var subscriptions: Int?
    var mrr: Int?
    var outstanding: Int?
    var aging: Aging?
    var suspended: Int?
    var pastDue: Int?

    var currencyCode: String { currency ?? "GEL" }

    var enforcementTone: StatusTone {
        switch (mode ?? "").lowercased() {
        case "on":      return .good
        case "dry_run": return .warning
        default:        return .neutral
        }
    }
}

/// `GET /api/sites/:id/logs` — parsed Laravel log entries.
struct SiteLogsResponse: Decodable, Sendable {
    struct Entry: Decodable, Sendable, Hashable, Identifiable {
        var timestamp: Date?
        var environment: String?
        var level: String?
        var message: String

        var id: String { "\(timestamp?.timeIntervalSince1970 ?? 0)-\(message.prefix(40))" }
        var tone: StatusTone { StatusTone(status: level) }
    }

    var entries: [Entry]
    var total: Int?
    var path: String?
}
