import Foundation

/// `GET /api/sites/:id/deploy/pending`
public struct DeployPending: Decodable, Sendable {
    public var branch: String?
    public var currentCommit: String?
    public var remoteCommit: String?
    public var upToDate: Bool
    public var range: Bool
    public var commits: [PendingCommit]

    public var shortCurrent: String { String((currentCommit ?? "").prefix(7)) }
    public var shortRemote: String { String((remoteCommit ?? "").prefix(7)) }
}

/// The `commits` array was empty on every site when the API was surveyed, so the exact
/// element shape is unknown. Decoded defensively: an element may be a plain string
/// (a subject line) or an object with any of the usual git field names.
public struct PendingCommit: Decodable, Sendable, Hashable {
    public var hash: String?
    public var message: String?
    public var author: String?
    public var date: Date?

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(JSONValue.self)

        if case .string(let text) = value {
            message = text
            return
        }

        hash = value["hash"]?.stringValue
            ?? value["sha"]?.stringValue
            ?? value["commit"]?.stringValue
            ?? value["id"]?.stringValue
        message = value["message"]?.stringValue
            ?? value["subject"]?.stringValue
            ?? value["title"]?.stringValue
        author = value["author"]?.stringValue
            ?? value["author"]?["name"]?.stringValue
            ?? value["authorName"]?.stringValue
        date = (value["date"] ?? value["createdAt"] ?? value["committedAt"])?
            .stringValue
            .flatMap(DateParsing.parse)
    }

    public var shortHash: String { String((hash ?? "").prefix(7)) }
}

/// `GET /api/sites/:id/releases`
public struct ReleasesResponse: Decodable, Sendable {
    public struct Release: Decodable, Sendable, Hashable, Identifiable {
        public var name: String
        public var isCurrent: Bool
        public var createdAt: Date?

        public var id: String { name }
    }

    public var releases: [Release]
    public var current: String?
}

/// `GET /api/sites/:id/test-stats`
public struct TestStats: Decodable, Sendable {
    public struct Run: Decodable, Sendable, Hashable {
        public var id: Int?
        public var commit: String?
        public var testResult: String?
        public var createdAt: Date?
        public var testsPassed: Int?
        public var testsFailed: Int?
        public var testsTotal: Int?
        public var testDurationMs: Int?
    }

    public struct TrendPoint: Decodable, Sendable, Hashable, Identifiable {
        public var date: Date
        public var result: String?
        public var passed: Int
        public var failed: Int
        public var total: Int

        public var id: Date { date }
        public var tone: StatusTone { StatusTone(status: result) }
    }

    public var totalRuns: Int?
    public var passRate: Int?
    public var avgDurationMs: Int?
    public var lastRun: Run?
    public var trend: [TrendPoint]
}

/// `GET /api/sites/:id/maintenance`
public struct MaintenanceState: Decodable, Sendable {
    public var maintenanceMode: Bool
}

/// `GET /api/sites/:id/supervisor/status`
public struct SupervisorStatus: Decodable, Sendable {
    public struct Process: Decodable, Sendable, Hashable, Identifiable {
        public var name: String
        public var state: String
        public var description: String?

        public var id: String { name }

        public var tone: StatusTone {
            switch state.uppercased() {
            case "RUNNING":                    return .good
            case "STARTING", "STOPPING":       return .info
            case "STOPPED", "EXITED":          return .warning
            case "FATAL", "BACKOFF", "UNKNOWN": return .critical
            default:                            return .neutral
            }
        }
    }

    public var processes: [Process]
}

/// `GET /api/sites/:id/supervisor` — the raw ini file.
public struct FileContents: Decodable, Sendable {
    public var content: String
    public var path: String?
    public var exists: Bool?
}

/// `GET /api/sites/:id/queue/stats` — both counters are nullable when the queue table
/// cannot be reached.
public struct QueueStats: Decodable, Sendable {
    public var pending: Int?
    public var failed: Int?
}

/// `GET /api/sites/:id/failed-jobs`. The array was empty when surveyed, so this decodes
/// whatever Laravel's `failed_jobs` row looks like without assuming key names.
public struct FailedJobsResponse: Decodable, Sendable {
    public var jobs: [FailedJob]
}

public struct FailedJob: Decodable, Sendable, Hashable, Identifiable {
    public var id: String
    public var uuid: String?
    public var connection: String?
    public var queue: String?
    public var jobName: String?
    public var exception: String?
    public var failedAt: Date?

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(JSONValue.self)
        uuid = value["uuid"]?.stringValue
        id = value["id"]?.stringValue ?? uuid ?? UUID().uuidString
        connection = value["connection"]?.stringValue
        queue = value["queue"]?.stringValue
        jobName = value["name"]?.stringValue
            ?? value["displayName"]?.stringValue
            ?? value["job"]?.stringValue
            ?? value["payload"]?["displayName"]?.stringValue
        exception = value["exception"]?.stringValue
        failedAt = (value["failedAt"] ?? value["failed_at"])?.stringValue.flatMap(DateParsing.parse)
    }

    /// Laravel exceptions are enormous; the first line is the useful part.
    public var exceptionHeadline: String {
        exception?.split(separator: "\n").first.map(String.init) ?? "Unknown failure"
    }

    /// The id the retry/delete routes expect.
    public var routeID: String { uuid ?? id }
}

/// `GET /api/sites/:id/artisan/commands`
public struct ArtisanCommandsResponse: Decodable, Sendable {
    public var commands: [ArtisanCommand]
}

public struct ArtisanCommand: Decodable, Sendable, Hashable, Identifiable {
    public var cmd: String
    public var label: String?
    public var description: String?
    public var group: String?

    public var id: String { cmd }
    public var displayName: String { label ?? cmd }
}
