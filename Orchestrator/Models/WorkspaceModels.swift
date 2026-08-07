import Foundation

// MARK: - Tasks

struct TasksResponse: Decodable, Sendable {
    var tasks: [WorkTask]
}

struct WorkTask: Decodable, Sendable, Hashable, Identifiable {
    struct Person: Decodable, Sendable, Hashable {
        var id: Int
        var email: String?
    }

    struct SiteRef: Decodable, Sendable, Hashable {
        var id: Int
        var domain: String?
        var name: String?
    }

    struct ChecklistItem: Decodable, Sendable, Hashable, Identifiable {
        var id: Int
        var taskId: Int?
        var text: String
        var done: Bool
        var position: Int?
    }

    struct Counts: Decodable, Sendable, Hashable {
        var comments: Int?
    }

    var id: Int
    var title: String
    var description: String?
    var status: String
    var priority: String?
    var position: Int?
    var dueDate: Date?
    var tags: String?
    var siteId: Int?
    var assigneeId: Int?
    var createdById: Int?
    var createdAt: Date?
    var updatedAt: Date?
    var assignee: Person?
    var createdBy: Person?
    var site: SiteRef?
    var checklist: [ChecklistItem]?
    var _count: Counts?

    var tagList: [String] { EmbeddedJSON.stringArray(from: tags) }
    var commentCount: Int { _count?.comments ?? 0 }
    var isDone: Bool { status.lowercased() == "done" || status.lowercased() == "completed" }

    var priorityTone: StatusTone {
        switch (priority ?? "").lowercased() {
        case "urgent", "critical", "high": return .critical
        case "medium", "normal":           return .warning
        case "low":                        return .neutral
        default:                            return .neutral
        }
    }

    var isOverdue: Bool {
        guard let dueDate, !isDone else { return false }
        return dueDate < .now
    }

    var checklistProgress: String? {
        guard let checklist, !checklist.isEmpty else { return nil }
        return "\(checklist.filter(\.done).count)/\(checklist.count)"
    }
}

struct TaskDraft: Encodable, Sendable {
    var title: String
    var description: String?
    var status: String?
    var priority: String?
    var dueDate: Date?
    var siteId: Int?
    var assigneeId: Int?
}

struct TaskPatch: Encodable, Sendable {
    var title: String?
    var description: String?
    var status: String?
    var priority: String?
    var dueDate: Date?
    var siteId: Int?
    var assigneeId: Int?
}

// MARK: - Notes

struct NotesResponse: Decodable, Sendable {
    var notes: [Note]
}

struct Note: Decodable, Sendable, Hashable, Identifiable {
    struct Owner: Decodable, Sendable, Hashable {
        var id: Int
        var email: String?
    }

    var id: Int
    var title: String
    var body: String?
    var pinned: Bool
    var isPublic: Bool
    var tags: String?
    var siteId: Int?
    var ownerId: Int?
    var createdAt: Date?
    var updatedAt: Date?
    var owner: Owner?
    var canEdit: Bool

    var tagList: [String] { EmbeddedJSON.stringArray(from: tags) }

    var preview: String {
        (body ?? "").split(separator: "\n").prefix(2).joined(separator: " ")
    }
}

struct NoteDraft: Encodable, Sendable {
    var title: String
    var body: String?
    var pinned: Bool?
    var isPublic: Bool?
    var siteId: Int?
}

// MARK: - Calendar

struct CalendarResponse: Decodable, Sendable {
    var events: [CalendarEvent]
}

struct CalendarEvent: Decodable, Sendable, Hashable, Identifiable {
    var id: Int
    var title: String
    var notes: String?
    var start: Date?
    var end: Date?
    var allDay: Bool
    var type: String?
    var repeats: String?
    var siteId: Int?

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(JSONValue.self)
        id = value["id"]?.intValue ?? 0
        title = value["title"]?.stringValue ?? "Event"
        notes = (value["notes"] ?? value["description"])?.stringValue
        start = (value["start"] ?? value["startsAt"] ?? value["date"])?.stringValue.flatMap(DateParsing.parse)
        end = (value["end"] ?? value["endsAt"])?.stringValue.flatMap(DateParsing.parse)
        allDay = (value["allDay"] ?? value["all_day"])?.boolValue ?? false
        type = value["type"]?.stringValue
        repeats = (value["repeats"] ?? value["recurrence"])?.stringValue
        siteId = value["siteId"]?.intValue
    }

    var tone: StatusTone {
        switch (type ?? "").lowercased() {
        case "maintenance": return .warning
        case "reminder":    return .info
        default:            return .neutral
        }
    }
}

struct CalendarEventDraft: Encodable, Sendable {
    var title: String
    var notes: String?
    var start: String
    var end: String?
    var allDay: Bool
    var type: String
    var siteId: Int?
}

// MARK: - AI

struct AIConfig: Decodable, Sendable, Hashable {
    var enabled: Bool
    var provider: String?
    var model: String?
    var baseUrl: String?
    var configured: Bool
    var usageToday: Int?
    var dailyLimit: Int?

    var usageLabel: String {
        guard let limit = dailyLimit, limit > 0 else { return "\(usageToday ?? 0) today" }
        return "\(usageToday ?? 0) / \(limit) today"
    }

    var isThrottled: Bool {
        guard let limit = dailyLimit, limit > 0 else { return false }
        return (usageToday ?? 0) >= limit
    }
}

struct AIChatMessage: Identifiable, Hashable, Sendable {
    enum Role: String, Codable, Sendable { case user, assistant }

    let id = UUID()
    var role: Role
    var text: String
}

/// The panel sends prior turns back as `history`.
struct AIChatTurn: Encodable, Sendable {
    var role: String
    var content: String
}

struct AIChatRequest: Encodable, Sendable {
    var message: String
    var siteId: Int?
    var history: [AIChatTurn]
}

struct AIChatResponse: Decodable, Sendable {
    var reply: String

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(JSONValue.self)
        reply = value["reply"]?.stringValue
            ?? value["message"]?.stringValue
            ?? value["content"]?.stringValue
            ?? value["answer"]?.stringValue
            ?? value["text"]?.stringValue
            ?? "(empty response)"
    }
}

// MARK: - Telegram, digest, audit

struct TelegramStatus: Decodable, Sendable, Hashable {
    var linked: Bool
    var username: String?
    var linkedAt: Date?
    var botConfigured: Bool
    var botUsername: String?
    var webhookConfigured: Bool
}

struct TelegramLinkCode: Decodable, Sendable {
    var code: String?
    var expiresAt: Date?
    var url: String?

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(JSONValue.self)
        code = (value["code"] ?? value["linkCode"] ?? value["token"])?.stringValue
        expiresAt = value["expiresAt"]?.stringValue.flatMap(DateParsing.parse)
        url = (value["url"] ?? value["link"] ?? value["deepLink"])?.stringValue
    }
}

struct DigestSettings: Decodable, Sendable {
    struct Preview: Decodable, Sendable, Hashable {
        var since: Date?
        var deploySuccess: Int?
        var deployFailed: Int?
        var uptimePct: Int?
        var avgMs: Int?
        var errOpen: Int?
        var errNew: Int?
        var sites: Int?
    }

    var enabled: Bool
    /// Weekday index, 0 = Sunday.
    var day: Int?
    var lastSent: String?
    var preview: Preview?
}

struct DigestPatch: Encodable, Sendable {
    var enabled: Bool?
    var day: Int?
}

struct AuditResponse: Decodable, Sendable {
    var logs: [AuditEntry]
    var total: Int?
    var limit: Int?
    var offset: Int?
}

struct AuditEntry: Decodable, Sendable, Hashable, Identifiable {
    var id: Int
    var action: String
    var siteId: Int?
    var userId: Int?
    var meta: JSONValue?
    var createdAt: Date?
    var userEmail: String?
    var userRole: String?

    var symbol: String {
        let key = action.lowercased()
        if key.contains("deploy")  { return "arrow.up.circle" }
        if key.contains("delete") || key.contains("remove") { return "trash" }
        if key.contains("login") || key.contains("auth")    { return "key" }
        if key.contains("token")   { return "key.horizontal" }
        if key.contains("ssl")     { return "lock.shield" }
        if key.contains("billing") || key.contains("invoice") { return "creditcard" }
        return "circle.dashed"
    }

    var tone: StatusTone {
        let key = action.lowercased()
        if key.contains("delete") || key.contains("remove") || key.contains("suspend") { return .critical }
        if key.contains("create") || key.contains("deploy") { return .info }
        return .neutral
    }

    var metaSummary: String? {
        guard let object = meta?.objectValue, !object.isEmpty else { return nil }
        return object
            .sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value.stringValue ?? "—")" }
            .joined(separator: " · ")
    }
}

// MARK: - Users & settings

struct UserDraft: Encodable, Sendable {
    var email: String
    var password: String
    var role: String
    var allSitesAccess: Bool
}

struct UserPatch: Encodable, Sendable {
    var email: String?
    var password: String?
    var role: String?
    var allSitesAccess: Bool?
}

struct UserSitesResponse: Decodable, Sendable {
    var siteIds: [Int]

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(JSONValue.self)
        if let array = value.arrayValue {
            siteIds = array.compactMap(\.intValue)
        } else if let array = value["siteIds"]?.arrayValue {
            siteIds = array.compactMap(\.intValue)
        } else if let array = value["sites"]?.arrayValue {
            siteIds = array.compactMap { $0.intValue ?? $0["id"]?.intValue }
        } else {
            siteIds = []
        }
    }
}

struct TwoFactorSetup: Decodable, Sendable {
    var qrDataUrl: String?
    var secret: String?
}

struct ChangePasswordRequest: Encodable, Sendable {
    var oldPassword: String
    var newPassword: String
}

struct CreateTokenRequest: Encodable, Sendable {
    var name: String
    var expiresInDays: Int?
}

struct CreatedToken: Decodable, Sendable {
    /// Returned once, at creation time, and never again.
    var token: String?
    var id: Int?
    var name: String?

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(JSONValue.self)
        let node = value["token"].flatMap { $0.objectValue != nil ? $0 : nil } ?? value
        token = value["token"]?.stringValue ?? value["plainTextToken"]?.stringValue ?? value["value"]?.stringValue
        id = node["id"]?.intValue
        name = node["name"]?.stringValue
    }
}

struct AlertRuleDraft: Encodable, Sendable {
    var metric: String
    var `operator`: String
    var threshold: Int
    var enabled: Bool
    var cooldownMins: Int?
}
