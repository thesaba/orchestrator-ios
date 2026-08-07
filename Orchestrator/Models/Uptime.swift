import Foundation

/// `GET /api/uptime`
struct UptimeOverview: Decodable, Sendable {
    struct Entry: Decodable, Sendable, Hashable, Identifiable {
        var siteId: Int
        var domain: String
        var monitoring: Bool
        var status: String?
        var responseMs: Int?
        var statusCode: Int?
        var checkedAt: Date?

        var id: Int { siteId }

        var tone: StatusTone {
            guard monitoring else { return .neutral }
            return StatusTone(status: status)
        }

        var isUp: Bool { (status ?? "").lowercased() == "up" }
    }

    var sites: [Entry]
}

/// `GET /api/uptime/:siteId/history`
struct UptimeHistory: Decodable, Sendable {
    struct Check: Decodable, Sendable, Hashable, Identifiable {
        var id: Int
        var siteId: Int
        var status: String?
        var responseMs: Int?
        var statusCode: Int?
        var checkedAt: Date

        var isUp: Bool { (status ?? "").lowercased() == "up" }
    }

    var checks: [Check]
    var uptime24h: Int?
}

/// `GET /api/uptime/:siteId/sparkline`
struct UptimeSparkline: Decodable, Sendable {
    struct Point: Decodable, Sendable, Hashable, Identifiable {
        var ms: Int?
        var status: String?
        var at: Date

        var id: Date { at }
        var isUp: Bool { (status ?? "").lowercased() == "up" }
    }

    var points: [Point]
}
