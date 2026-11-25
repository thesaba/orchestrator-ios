import Foundation

/// `GET /api/notifications`
public struct NotificationsResponse: Decodable, Sendable {
    public var notifications: [AppNotification]
    public var unread: Int?
}

public struct AppNotification: Identifiable, Decodable, Sendable, Hashable {
    public var id: Int
    public var type: String?
    public var level: String?
    public var title: String
    public var body: String?
    /// JSON encoded inside a string, e.g. `{"siteId":6,"domain":"netflow.ge"}`.
    public var meta: String?
    public var read: Bool
    public var createdAt: Date?

    public var tone: StatusTone { StatusTone(status: level) }

    public var symbol: String {
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
    public var siteId: Int? { metaObject?["siteId"]?.intValue }
    public var domain: String? { metaObject?["domain"]?.stringValue }
}

/// `GET /api/log-errors` — the panel's mini-Sentry.
public struct LogErrorsResponse: Decodable, Sendable {
    public var errors: [LogError]
    public var unresolved: Int?
}

public struct LogError: Identifiable, Decodable, Sendable, Hashable {
    public struct SiteRef: Decodable, Sendable, Hashable {
        public var domain: String?
    }

    public var id: Int
    public var siteId: Int?
    public var level: String?
    public var exceptionClass: String?
    public var message: String?
    public var count: Int?
    public var firstSeenAt: Date?
    public var lastSeenAt: Date?
    public var resolved: Bool
    public var ignored: Bool
    public var site: SiteRef?

    public var tone: StatusTone {
        if resolved || ignored { return .neutral }
        return StatusTone(status: level)
    }

    public var headline: String { exceptionClass ?? level?.capitalized ?? "Error" }
}

/// `GET /api/alerts`
public struct AlertRulesResponse: Decodable, Sendable {
    public var rules: [AlertRule]
}

public struct AlertRule: Identifiable, Decodable, Sendable, Hashable {
    public var id: Int
    public var metric: String
    public var comparison: String
    public var threshold: Int
    public var enabled: Bool
    public var cooldownMins: Int?
    public var lastTriggeredAt: Date?
    public var createdAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id, metric, threshold, enabled, cooldownMins, lastTriggeredAt, createdAt
        case comparison = "operator"
    }

    public var summary: String { "\(metric) \(comparison) \(threshold)" }
}

/// `GET /api/billing/overview` — every amount is integer minor units (თეთრი).
public struct BillingOverview: Decodable, Sendable, Hashable {
    public struct Aging: Decodable, Sendable, Hashable {
        public var current: Int?
        public var d1_30: Int?
        public var d31_60: Int?
        public var d61_plus: Int?
        public var total: Int?
    }

    public var mode: String?
    public var currency: String?
    public var clients: Int?
    public var subscriptions: Int?
    public var mrr: Int?
    public var outstanding: Int?
    public var aging: Aging?
    public var suspended: Int?
    public var pastDue: Int?

    public var currencyCode: String { currency ?? "GEL" }

    public var enforcementTone: StatusTone {
        switch (mode ?? "").lowercased() {
        case "on":      return .good
        case "dry_run": return .warning
        default:        return .neutral
        }
    }
}

/// `GET /api/sites/:id/logs` — parsed Laravel log entries.
public struct SiteLogsResponse: Decodable, Sendable {
    public struct Entry: Decodable, Sendable, Hashable, Identifiable {
        public var timestamp: Date?
        public var environment: String?
        public var level: String?
        public var message: String

        public var id: String { "\(timestamp?.timeIntervalSince1970 ?? 0)-\(message.prefix(40))" }
        public var tone: StatusTone { StatusTone(status: level) }
    }

    public var entries: [Entry]
    public var total: Int?
    public var path: String?
}
