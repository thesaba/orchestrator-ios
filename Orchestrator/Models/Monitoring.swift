import Foundation

/// `GET /api/monitor/history` — one sample per minute, so 24 h is ~1440 points.
struct MonitorHistory: Decodable, Sendable {
    struct Sample: Decodable, Sendable, Hashable, Identifiable {
        var cpuPercent: Int?
        var ramPercent: Int?
        var diskPercent: Int?
        var checkedAt: Date

        var id: Date { checkedAt }
    }

    var hours: Int?
    var samples: [Sample]

    /// Charts choke on ~1400 points; average into evenly spaced buckets first.
    func downsampled(to buckets: Int = 120) -> [Sample] {
        guard buckets > 0, samples.count > buckets else { return samples }
        let size = Int((Double(samples.count) / Double(buckets)).rounded(.up))
        return stride(from: 0, to: samples.count, by: size).map { start in
            let slice = Array(samples[start..<min(start + size, samples.count)])
            func mean(_ path: (Sample) -> Int?) -> Int? {
                let values = slice.compactMap(path)
                guard !values.isEmpty else { return nil }
                return values.reduce(0, +) / values.count
            }
            return Sample(
                cpuPercent: mean { $0.cpuPercent },
                ramPercent: mean { $0.ramPercent },
                diskPercent: mean { $0.diskPercent },
                checkedAt: slice[0].checkedAt
            )
        }
    }
}

/// `GET /api/monitor/stats/history` — deploy success/fail per day.
struct DeployStatsHistory: Decodable, Sendable {
    struct Day: Decodable, Sendable, Hashable, Identifiable {
        var date: Date
        var success: Int
        var failed: Int

        var id: Date { date }
        var total: Int { success + failed }
    }

    var days: [Day]
}

/// `GET /api/monitor/processes`
struct ProcessSnapshot: Decodable, Sendable {
    struct Entry: Decodable, Sendable, Hashable, Identifiable {
        var name: String
        var cpuPercent: Double?
        var memPercent: Double?
        var rssBytes: Int?
        var count: Int?

        var id: String { name }
    }

    var cores: Int?
    var services: [Entry]
    var capturedAt: Date?
}

/// `GET /api/monitor/apm`
struct APMOverview: Decodable, Sendable {
    struct SiteEntry: Decodable, Sendable, Hashable, Identifiable {
        var siteId: Int
        var domain: String
        var samples: Int?
        var uptimePct: Int?
        var avg: Int?
        var p50: Int?
        var p95: Int?
        var p99: Int?
        var max: Int?

        var id: Int { siteId }

        var tone: StatusTone {
            guard let uptime = uptimePct else { return .neutral }
            if uptime >= 99 { return .good }
            if uptime >= 95 { return .warning }
            return .critical
        }
    }

    var hours: Int?
    var sites: [SiteEntry]
}

/// `GET /api/monitor/services`
struct ServiceStatus: Decodable, Sendable, Hashable, Identifiable {
    var key: String
    var name: String
    var status: String

    var id: String { key }
    var tone: StatusTone { StatusTone(status: status) }
}

/// `GET /api/monitor/ssl`
struct SSLOverview: Decodable, Sendable {
    struct Entry: Decodable, Sendable, Hashable, Identifiable {
        var siteId: Int
        var domain: String
        var daysLeft: Int?
        var expiresAt: Date?
        var error: String?

        var id: Int { siteId }

        var tone: StatusTone {
            if error != nil { return .critical }
            guard let daysLeft else { return .neutral }
            if daysLeft <= 7 { return .critical }
            if daysLeft <= 21 { return .warning }
            return .good
        }
    }

    var sites: [Entry]
}

/// `GET /api/sites/:id/ssl`
struct SiteSSL: Decodable, Sendable, Hashable {
    var active: Bool
    var expiresAt: Date?
    var issuer: String?
    var daysLeft: Int?
    var sslEnabled: Bool
    var running: Bool
}

/// `GET /api/system/info`
struct SystemInfo: Decodable, Sendable, Hashable {
    var hostname: String?
    var kernel: String?
    var os: String?
    var uptimeSeconds: Int?
    var pendingUpdates: Int?
    var rebootRequired: Bool
    var ufwStatus: String?
}
