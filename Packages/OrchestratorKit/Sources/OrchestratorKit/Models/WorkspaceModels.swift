import Foundation

// MARK: - Tasks

public struct TasksResponse: Decodable, Sendable {
    public var tasks: [WorkTask]
}

public struct WorkTask: Decodable, Sendable, Hashable, Identifiable {
    public struct Person: Decodable, Sendable, Hashable {
        public var id: Int
        public var email: String?
    }

    public struct SiteRef: Decodable, Sendable, Hashable {
        public var id: Int
        public var domain: String?
        public var name: String?
    }

    public struct ChecklistItem: Decodable, Sendable, Hashable, Identifiable {
        public var id: Int
        public var taskId: Int?
        public var text: String
        public var done: Bool
        public var position: Int?
    }

    public struct Counts: Decodable, Sendable, Hashable {
        public var comments: Int?
    }

    public var id: Int
    public var title: String
    public var description: String?
    public var status: String
    public var priority: String?
    public var position: Int?
    public var dueDate: Date?
    public var tags: String?
    public var siteId: Int?
    public var assigneeId: Int?
    public var createdById: Int?
    public var createdAt: Date?
    public var updatedAt: Date?
    public var assignee: Person?
    public var createdBy: Person?
    public var site: SiteRef?
    public var checklist: [ChecklistItem]?
    public var _count: Counts?

    public var tagList: [String] { EmbeddedJSON.stringArray(from: tags) }
    public var commentCount: Int { _count?.comments ?? 0 }
    public var isDone: Bool { status.lowercased() == "done" || status.lowercased() == "completed" }

    public var priorityTone: StatusTone {
        switch (priority ?? "").lowercased() {
        case "urgent", "critical", "high": return .critical
        case "medium", "normal":           return .warning
        case "low":                        return .neutral
        default:                            return .neutral
        }
    }

    public var isOverdue: Bool {
        guard let dueDate, !isDone else { return false }
        return dueDate < .now
    }

    public var checklistProgress: String? {
        guard let checklist, !checklist.isEmpty else { return nil }
        return "\(checklist.filter(\.done).count)/\(checklist.count)"
    }
}

public struct TaskDraft: Encodable, Sendable {
    public var title: String
    public var description: String?
    public var status: String?
    public var priority: String?
    public var dueDate: Date?
    public var siteId: Int?
    public var assigneeId: Int?

    public init(title: String, description: String? = nil, status: String? = nil, priority: String? = nil,
                dueDate: Date? = nil, siteId: Int? = nil, assigneeId: Int? = nil) {
        self.title = title
        self.description = description
        self.status = status
        self.priority = priority
        self.dueDate = dueDate
        self.siteId = siteId
        self.assigneeId = assigneeId
    }
}

public struct TaskPatch: Encodable, Sendable {
    public var title: String?
    public var description: String?
    public var status: String?
    public var priority: String?
    public var dueDate: Date?
    public var siteId: Int?
    public var assigneeId: Int?

    public init(title: String? = nil, description: String? = nil, status: String? = nil, priority: String? = nil, dueDate: Date? = nil, siteId: Int? = nil, assigneeId: Int? = nil) {
        self.title = title
        self.description = description
        self.status = status
        self.priority = priority
        self.dueDate = dueDate
        self.siteId = siteId
        self.assigneeId = assigneeId
    }
}

// MARK: - Notes

public struct NotesResponse: Decodable, Sendable {
    public var notes: [Note]
}

public struct Note: Decodable, Sendable, Hashable, Identifiable {
    public struct Owner: Decodable, Sendable, Hashable {
        public var id: Int
        public var email: String?
    }

    public var id: Int
    public var title: String
    public var body: String?
    public var pinned: Bool
    public var isPublic: Bool
    public var tags: String?
    public var siteId: Int?
    public var ownerId: Int?
    public var createdAt: Date?
    public var updatedAt: Date?
    public var owner: Owner?
    public var canEdit: Bool

    public var tagList: [String] { EmbeddedJSON.stringArray(from: tags) }

    public var preview: String {
        (body ?? "").split(separator: "\n").prefix(2).joined(separator: " ")
    }
}

public struct NoteDraft: Encodable, Sendable {
    public var title: String
    public var body: String?
    public var pinned: Bool?
    public var isPublic: Bool?
    public var siteId: Int?

    public init(title: String, body: String? = nil, pinned: Bool? = nil, isPublic: Bool? = nil, siteId: Int? = nil) {
        self.title = title
        self.body = body
        self.pinned = pinned
        self.isPublic = isPublic
        self.siteId = siteId
    }
}

// MARK: - Calendar

public struct CalendarResponse: Decodable, Sendable {
    public var events: [CalendarEvent]
}

public struct CalendarEvent: Decodable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var title: String
    public var notes: String?
    public var start: Date?
    public var end: Date?
    public var allDay: Bool
    public var type: String?
    public var repeats: String?
    public var siteId: Int?

    public init(from decoder: Decoder) throws {
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

    public var tone: StatusTone {
        switch (type ?? "").lowercased() {
        case "maintenance": return .warning
        case "reminder":    return .info
        default:            return .neutral
        }
    }
}

public struct CalendarEventDraft: Encodable, Sendable {
    public var title: String
    public var notes: String?
    public var start: String
    public var end: String?
    public var allDay: Bool
    public var type: String
    public var siteId: Int?

    public init(title: String, notes: String? = nil, start: String, end: String? = nil, allDay: Bool, type: String, siteId: Int? = nil) {
        self.title = title
        self.notes = notes
        self.start = start
        self.end = end
        self.allDay = allDay
        self.type = type
        self.siteId = siteId
    }
}

// MARK: - AI

public struct AIConfig: Decodable, Sendable, Hashable {
    public var enabled: Bool
    public var provider: String?
    public var model: String?
    public var baseUrl: String?
    public var configured: Bool
    public var usageToday: Int?
    public var dailyLimit: Int?

    public var usageLabel: String {
        guard let limit = dailyLimit, limit > 0 else { return "\(usageToday ?? 0) today" }
        return "\(usageToday ?? 0) / \(limit) today"
    }

    public var isThrottled: Bool {
        guard let limit = dailyLimit, limit > 0 else { return false }
        return (usageToday ?? 0) >= limit
    }
}

public struct AIChatMessage: Identifiable, Hashable, Sendable {
    public enum Role: String, Codable, Sendable { case user, assistant }

    public let id = UUID()
    public var role: Role
    public var text: String

    public init(role: Role, text: String) {
        self.role = role
        self.text = text
    }
}

/// The panel sends prior turns back as `history`.
public struct AIChatTurn: Encodable, Sendable {
    public var role: String
    public var content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

public struct AIChatRequest: Encodable, Sendable {
    public var message: String
    public var siteId: Int?
    public var history: [AIChatTurn]

    public init(message: String, siteId: Int? = nil, history: [AIChatTurn]) {
        self.message = message
        self.siteId = siteId
        self.history = history
    }
}

public struct AIChatResponse: Decodable, Sendable {
    public var reply: String

    public init(from decoder: Decoder) throws {
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

public struct TelegramStatus: Decodable, Sendable, Hashable {
    public var linked: Bool
    public var username: String?
    public var linkedAt: Date?
    public var botConfigured: Bool
    public var botUsername: String?
    public var webhookConfigured: Bool
}

public struct TelegramLinkCode: Decodable, Sendable {
    public var code: String?
    public var expiresAt: Date?
    public var url: String?

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(JSONValue.self)
        code = (value["code"] ?? value["linkCode"] ?? value["token"])?.stringValue
        expiresAt = value["expiresAt"]?.stringValue.flatMap(DateParsing.parse)
        url = (value["url"] ?? value["link"] ?? value["deepLink"])?.stringValue
    }
}

public struct DigestSettings: Decodable, Sendable {
    public struct Preview: Decodable, Sendable, Hashable {
        public var since: Date?
        public var deploySuccess: Int?
        public var deployFailed: Int?
        public var uptimePct: Int?
        public var avgMs: Int?
        public var errOpen: Int?
        public var errNew: Int?
        public var sites: Int?
    }

    public var enabled: Bool
    /// Weekday index, 0 = Sunday.
    public var day: Int?
    public var lastSent: String?
    public var preview: Preview?
}

public struct DigestPatch: Encodable, Sendable {
    public var enabled: Bool?
    public var day: Int?

    public init(enabled: Bool? = nil, day: Int? = nil) {
        self.enabled = enabled
        self.day = day
    }
}

public struct AuditResponse: Decodable, Sendable {
    public var logs: [AuditEntry]
    public var total: Int?
    public var limit: Int?
    public var offset: Int?
}

public struct AuditEntry: Decodable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var action: String
    public var siteId: Int?
    public var userId: Int?
    public var meta: JSONValue?
    public var createdAt: Date?
    public var userEmail: String?
    public var userRole: String?

    public var symbol: String {
        let key = action.lowercased()
        if key.contains("deploy")  { return "arrow.up.circle" }
        if key.contains("delete") || key.contains("remove") { return "trash" }
        if key.contains("login") || key.contains("auth")    { return "key" }
        if key.contains("token")   { return "key.horizontal" }
        if key.contains("ssl")     { return "lock.shield" }
        if key.contains("billing") || key.contains("invoice") { return "creditcard" }
        return "circle.dashed"
    }

    public var tone: StatusTone {
        let key = action.lowercased()
        if key.contains("delete") || key.contains("remove") || key.contains("suspend") { return .critical }
        if key.contains("create") || key.contains("deploy") { return .info }
        return .neutral
    }

    public var metaSummary: String? {
        guard let object = meta?.objectValue, !object.isEmpty else { return nil }
        return object
            .sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value.stringValue ?? "—")" }
            .joined(separator: " · ")
    }
}

// MARK: - Users & settings

public struct UserDraft: Encodable, Sendable {
    public var email: String
    public var password: String
    public var role: String
    public var allSitesAccess: Bool

    public init(email: String, password: String, role: String, allSitesAccess: Bool) {
        self.email = email
        self.password = password
        self.role = role
        self.allSitesAccess = allSitesAccess
    }
}

public struct UserPatch: Encodable, Sendable {
    public var email: String?
    public var password: String?
    public var role: String?
    public var allSitesAccess: Bool?

    public init(email: String? = nil, password: String? = nil, role: String? = nil, allSitesAccess: Bool? = nil) {
        self.email = email
        self.password = password
        self.role = role
        self.allSitesAccess = allSitesAccess
    }
}

public struct UserSitesResponse: Decodable, Sendable {
    public var siteIds: [Int]

    public init(from decoder: Decoder) throws {
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

public struct TwoFactorSetup: Decodable, Sendable {
    public var qrDataUrl: String?
    public var secret: String?
}

public struct ChangePasswordRequest: Encodable, Sendable {
    public var oldPassword: String
    public var newPassword: String

    public init(oldPassword: String, newPassword: String) {
        self.oldPassword = oldPassword
        self.newPassword = newPassword
    }
}

public struct CreateTokenRequest: Encodable, Sendable {
    public var name: String
    public var expiresInDays: Int?

    public init(name: String, expiresInDays: Int? = nil) {
        self.name = name
        self.expiresInDays = expiresInDays
    }
}

public struct CreatedToken: Decodable, Sendable {
    /// Returned once, at creation time, and never again.
    public var token: String?
    public var id: Int?
    public var name: String?

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(JSONValue.self)
        let node = value["token"].flatMap { $0.objectValue != nil ? $0 : nil } ?? value
        token = value["token"]?.stringValue ?? value["plainTextToken"]?.stringValue ?? value["value"]?.stringValue
        id = node["id"]?.intValue
        name = node["name"]?.stringValue
    }
}

public struct AlertRuleDraft: Encodable, Sendable {
    public var metric: String
    public var `operator`: String
    public var threshold: Int
    public var enabled: Bool
    public var cooldownMins: Int?

    public init(metric: String, operator: String, threshold: Int, enabled: Bool, cooldownMins: Int? = nil) {
        self.metric = metric
        self.operator = `operator`
        self.threshold = threshold
        self.enabled = enabled
        self.cooldownMins = cooldownMins
    }
}
