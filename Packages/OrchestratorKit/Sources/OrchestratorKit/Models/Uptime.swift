import Foundation

/// `GET /api/uptime`
public struct UptimeOverview: Decodable, Sendable {
    public struct Entry: Decodable, Sendable, Hashable, Identifiable {
        public var siteId: Int
        public var domain: String
        public var monitoring: Bool
        public var status: String?
        public var responseMs: Int?
        public var statusCode: Int?
        public var checkedAt: Date?

        public var id: Int { siteId }

        public var tone: StatusTone {
            guard monitoring else { return .neutral }
            return StatusTone(status: status)
        }

        public var isUp: Bool { (status ?? "").lowercased() == "up" }
    }

    public var sites: [Entry]
}

/// `GET /api/uptime/:siteId/history`
public struct UptimeHistory: Decodable, Sendable {
    public struct Check: Decodable, Sendable, Hashable, Identifiable {
        public var id: Int
        public var siteId: Int
        public var status: String?
        public var responseMs: Int?
        public var statusCode: Int?
        public var checkedAt: Date

        public var isUp: Bool { (status ?? "").lowercased() == "up" }
    }

    public var checks: [Check]
    public var uptime24h: Int?
}

/// `GET /api/uptime/:siteId/sparkline`
public struct UptimeSparkline: Decodable, Sendable {
    public struct Point: Decodable, Sendable, Hashable, Identifiable {
        public var ms: Int?
        public var status: String?
        public var at: Date

        public var id: Date { at }
        public var isUp: Bool { (status ?? "").lowercased() == "up" }
    }

    public var points: [Point]
}
