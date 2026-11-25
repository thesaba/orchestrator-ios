import Foundation

/// `GET /api/monitor/history` — one sample per minute, so 24 h is ~1440 points.
public struct MonitorHistory: Decodable, Sendable {
    public struct Sample: Decodable, Sendable, Hashable, Identifiable {
        public var cpuPercent: Int?
        public var ramPercent: Int?
        public var diskPercent: Int?
        public var checkedAt: Date

        public var id: Date { checkedAt }
    }

    public var hours: Int?
    public var samples: [Sample]

    /// Charts choke on ~1400 points; average into evenly spaced buckets first.
    public func downsampled(to buckets: Int = 120) -> [Sample] {
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
public struct DeployStatsHistory: Decodable, Sendable {
    public struct Day: Decodable, Sendable, Hashable, Identifiable {
        public var date: Date
        public var success: Int
        public var failed: Int

        public var id: Date { date }
        public var total: Int { success + failed }
    }

    public var days: [Day]
}

/// `GET /api/monitor/processes`
public struct ProcessSnapshot: Decodable, Sendable {
    public struct Entry: Decodable, Sendable, Hashable, Identifiable {
        public var name: String
        public var cpuPercent: Double?
        public var memPercent: Double?
        public var rssBytes: Int?
        public var count: Int?

        public var id: String { name }
    }

    public var cores: Int?
    public var services: [Entry]
    public var capturedAt: Date?
}

/// `GET /api/monitor/apm`
public struct APMOverview: Decodable, Sendable {
    public struct SiteEntry: Decodable, Sendable, Hashable, Identifiable {
        public var siteId: Int
        public var domain: String
        public var samples: Int?
        public var uptimePct: Int?
        public var avg: Int?
        public var p50: Int?
        public var p95: Int?
        public var p99: Int?
        public var max: Int?

        public var id: Int { siteId }

        public var tone: StatusTone {
            guard let uptime = uptimePct else { return .neutral }
            if uptime >= 99 { return .good }
            if uptime >= 95 { return .warning }
            return .critical
        }
    }

    public var hours: Int?
    public var sites: [SiteEntry]
}

/// `GET /api/monitor/services`
public struct ServiceStatus: Decodable, Sendable, Hashable, Identifiable {
    public var key: String
    public var name: String
    public var status: String

    public var id: String { key }
    public var tone: StatusTone { StatusTone(status: status) }
}

/// `GET /api/monitor/ssl`
public struct SSLOverview: Decodable, Sendable {
    public struct Entry: Decodable, Sendable, Hashable, Identifiable {
        public var siteId: Int
        public var domain: String
        public var daysLeft: Int?
        public var expiresAt: Date?
        public var error: String?

        public var id: Int { siteId }

        public var tone: StatusTone {
            if error != nil { return .critical }
            guard let daysLeft else { return .neutral }
            if daysLeft <= 7 { return .critical }
            if daysLeft <= 21 { return .warning }
            return .good
        }
    }

    public var sites: [Entry]
}

/// `GET /api/sites/:id/ssl`
public struct SiteSSL: Decodable, Sendable, Hashable {
    public var active: Bool
    public var expiresAt: Date?
    public var issuer: String?
    public var daysLeft: Int?
    public var sslEnabled: Bool
    public var running: Bool
}

/// `GET /api/system/info`
public struct SystemInfo: Decodable, Sendable, Hashable {
    public var hostname: String?
    public var kernel: String?
    public var os: String?
    public var uptimeSeconds: Int?
    public var pendingUpdates: Int?
    public var rebootRequired: Bool
    public var ufwStatus: String?
}
