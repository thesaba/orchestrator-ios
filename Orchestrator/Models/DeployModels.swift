import Foundation

/// `GET /api/sites/:id/deploy/pending`
struct DeployPending: Decodable, Sendable {
    var branch: String?
    var currentCommit: String?
    var remoteCommit: String?
    var upToDate: Bool
    var range: Bool
    var commits: [PendingCommit]

    var shortCurrent: String { String((currentCommit ?? "").prefix(7)) }
    var shortRemote: String { String((remoteCommit ?? "").prefix(7)) }
}

/// The `commits` array was empty on every site when the API was surveyed, so the exact
/// element shape is unknown. Decoded defensively: an element may be a plain string
/// (a subject line) or an object with any of the usual git field names.
struct PendingCommit: Decodable, Sendable, Hashable {
    var hash: String?
    var message: String?
    var author: String?
    var date: Date?

    init(from decoder: Decoder) throws {
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

    var shortHash: String { String((hash ?? "").prefix(7)) }
}

/// `GET /api/sites/:id/releases`
struct ReleasesResponse: Decodable, Sendable {
    struct Release: Decodable, Sendable, Hashable, Identifiable {
        var name: String
        var isCurrent: Bool
        var createdAt: Date?

        var id: String { name }
    }

    var releases: [Release]
    var current: String?
}

/// `GET /api/sites/:id/test-stats`
struct TestStats: Decodable, Sendable {
    struct Run: Decodable, Sendable, Hashable {
        var id: Int?
        var commit: String?
        var testResult: String?
        var createdAt: Date?
        var testsPassed: Int?
        var testsFailed: Int?
        var testsTotal: Int?
        var testDurationMs: Int?
    }

    struct TrendPoint: Decodable, Sendable, Hashable, Identifiable {
        var date: Date
        var result: String?
        var passed: Int
        var failed: Int
        var total: Int

        var id: Date { date }
        var tone: StatusTone { StatusTone(status: result) }
    }

    var totalRuns: Int?
    var passRate: Int?
    var avgDurationMs: Int?
    var lastRun: Run?
    var trend: [TrendPoint]
}

/// `GET /api/sites/:id/maintenance`
struct MaintenanceState: Decodable, Sendable {
    var maintenanceMode: Bool
}

/// `GET /api/sites/:id/supervisor/status`
struct SupervisorStatus: Decodable, Sendable {
    struct Process: Decodable, Sendable, Hashable, Identifiable {
        var name: String
        var state: String
        var description: String?

        var id: String { name }

        var tone: StatusTone {
            switch state.uppercased() {
            case "RUNNING":                    return .good
            case "STARTING", "STOPPING":       return .info
            case "STOPPED", "EXITED":          return .warning
            case "FATAL", "BACKOFF", "UNKNOWN": return .critical
            default:                            return .neutral
            }
        }
    }

    var processes: [Process]
}

/// `GET /api/sites/:id/supervisor` — the raw ini file.
struct FileContents: Decodable, Sendable {
    var content: String
    var path: String?
    var exists: Bool?
}

/// `GET /api/sites/:id/queue/stats` — both counters are nullable when the queue table
/// cannot be reached.
struct QueueStats: Decodable, Sendable {
    var pending: Int?
    var failed: Int?
}

/// `GET /api/sites/:id/failed-jobs`. The array was empty when surveyed, so this decodes
/// whatever Laravel's `failed_jobs` row looks like without assuming key names.
struct FailedJobsResponse: Decodable, Sendable {
    var jobs: [FailedJob]
}

struct FailedJob: Decodable, Sendable, Hashable, Identifiable {
    var id: String
    var uuid: String?
    var connection: String?
    var queue: String?
    var jobName: String?
    var exception: String?
    var failedAt: Date?

    init(from decoder: Decoder) throws {
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
    var exceptionHeadline: String {
        exception?.split(separator: "\n").first.map(String.init) ?? "Unknown failure"
    }

    /// The id the retry/delete routes expect.
    var routeID: String { uuid ?? id }
}

/// `GET /api/sites/:id/artisan/commands`
struct ArtisanCommandsResponse: Decodable, Sendable {
    var commands: [ArtisanCommand]
}

struct ArtisanCommand: Decodable, Sendable, Hashable, Identifiable {
    var cmd: String
    var label: String?
    var description: String?
    var group: String?

    var id: String { cmd }
    var displayName: String { label ?? cmd }
}
