import Foundation

// Tasks, notes, calendar, AI assistant, Telegram, digest, alerts, audit, users and settings.

extension OrchestratorAPI {

    // MARK: - Tasks

    public func tasks(siteID: Int? = nil, status: String? = nil, mineOnly: Bool = false) async throws -> [WorkTask] {
        var query: [URLQueryItem] = []
        if let siteID { query.append(URLQueryItem(name: "siteId", value: String(siteID))) }
        if let status, !status.isEmpty { query.append(URLQueryItem(name: "status", value: status)) }
        if mineOnly { query.append(URLQueryItem(name: "mine", value: "1")) }
        return try await client.get("/tasks", query: query, as: TasksResponse.self).tasks
    }

    @discardableResult
    public func createTask(_ draft: TaskDraft) async throws -> Data {
        try await client.send(.post, "/tasks", body: draft)
    }

    @discardableResult
    public func updateTask(id: Int, _ patch: TaskPatch) async throws -> Data {
        try await client.send(.patch, "/tasks/\(id)", body: patch)
    }

    @discardableResult
    public func deleteTask(id: Int) async throws -> Data {
        try await client.send(.delete, "/tasks/\(id)")
    }

    private struct TextBody: Encodable, Sendable { var text: String }
    private struct DoneBody: Encodable, Sendable { var done: Bool }
    private struct CommentBody: Encodable, Sendable { var body: String }

    @discardableResult
    public func addChecklistItem(taskID: Int, text: String) async throws -> Data {
        try await client.send(.post, "/tasks/\(taskID)/checklist", body: TextBody(text: text))
    }

    @discardableResult
    public func setChecklistItem(taskID: Int, itemID: Int, done: Bool) async throws -> Data {
        try await client.send(.patch, "/tasks/\(taskID)/checklist/\(itemID)", body: DoneBody(done: done))
    }

    @discardableResult
    public func removeChecklistItem(taskID: Int, itemID: Int) async throws -> Data {
        try await client.send(.delete, "/tasks/\(taskID)/checklist/\(itemID)")
    }

    @discardableResult
    public func addTaskComment(taskID: Int, body: String) async throws -> Data {
        try await client.send(.post, "/tasks/\(taskID)/comments", body: CommentBody(body: body))
    }

    // MARK: - Notes

    public func notes(search: String? = nil, siteID: Int? = nil) async throws -> [Note] {
        var query: [URLQueryItem] = []
        if let search, !search.isEmpty { query.append(URLQueryItem(name: "search", value: search)) }
        if let siteID { query.append(URLQueryItem(name: "siteId", value: String(siteID))) }
        return try await client.get("/notes", query: query, as: NotesResponse.self).notes
    }

    @discardableResult
    public func createNote(_ draft: NoteDraft) async throws -> Data {
        try await client.send(.post, "/notes", body: draft)
    }

    @discardableResult
    public func updateNote(id: Int, _ draft: NoteDraft) async throws -> Data {
        try await client.send(.patch, "/notes/\(id)", body: draft)
    }

    @discardableResult
    public func deleteNote(id: Int) async throws -> Data {
        try await client.send(.delete, "/notes/\(id)")
    }

    // MARK: - Calendar

    public func calendarEvents(start: Date, end: Date, siteID: Int? = nil) async throws -> [CalendarEvent] {
        let formatter = ISO8601DateFormatter()
        var query = [
            URLQueryItem(name: "start", value: formatter.string(from: start)),
            URLQueryItem(name: "end", value: formatter.string(from: end))
        ]
        if let siteID { query.append(URLQueryItem(name: "siteId", value: String(siteID))) }
        return try await client.get("/calendar/events", query: query, as: CalendarResponse.self).events
    }

    @discardableResult
    public func createCalendarEvent(_ draft: CalendarEventDraft) async throws -> Data {
        try await client.send(.post, "/calendar/events", body: draft)
    }

    @discardableResult
    public func deleteCalendarEvent(id: Int) async throws -> Data {
        try await client.send(.delete, "/calendar/events/\(id)")
    }

    // MARK: - AI

    public func aiConfig() async throws -> AIConfig {
        try await client.get("/ai/config")
    }

    @discardableResult
    public func testAI() async throws -> Data {
        try await client.send(.post, "/ai/test")
    }

    public func aiChat(message: String, siteID: Int?, history: [AIChatMessage]) async throws -> AIChatResponse {
        try await client.post(
            "/ai/chat",
            body: AIChatRequest(
                message: message,
                siteId: siteID,
                history: history.map { AIChatTurn(role: $0.role.rawValue, content: $0.text) }
            )
        )
    }

    public func explainError(_ errorID: Int, force: Bool = false) async throws -> AIChatResponse {
        try await client.post(
            "/ai/explain-error/\(errorID)",
            query: force ? [URLQueryItem(name: "force", value: "1")] : []
        )
    }

    public func explainDeploy(_ deploymentID: Int) async throws -> AIChatResponse {
        try await client.post("/ai/explain-deploy/\(deploymentID)")
    }

    // MARK: - Log errors

    @discardableResult
    public func setLogErrorResolved(_ id: Int, resolved: Bool) async throws -> Data {
        struct Body: Encodable, Sendable { var resolved: Bool }
        return try await client.send(.patch, "/log-errors/\(id)", body: Body(resolved: resolved))
    }

    @discardableResult
    public func setLogErrorIgnored(_ id: Int, ignored: Bool) async throws -> Data {
        struct Body: Encodable, Sendable { var ignored: Bool }
        return try await client.send(.patch, "/log-errors/\(id)", body: Body(ignored: ignored))
    }

    @discardableResult
    public func deleteLogError(_ id: Int) async throws -> Data {
        try await client.send(.delete, "/log-errors/\(id)")
    }

    // MARK: - Alerts

    @discardableResult
    public func createAlertRule(_ draft: AlertRuleDraft) async throws -> Data {
        try await client.send(.post, "/alerts", body: draft)
    }

    @discardableResult
    public func updateAlertRule(id: Int, _ draft: AlertRuleDraft) async throws -> Data {
        try await client.send(.patch, "/alerts/\(id)", body: draft)
    }

    @discardableResult
    public func deleteAlertRule(id: Int) async throws -> Data {
        try await client.send(.delete, "/alerts/\(id)")
    }

    // MARK: - Telegram & digest

    public func telegramStatus() async throws -> TelegramStatus {
        try await client.get("/telegram/me")
    }

    public func telegramLinkCode() async throws -> TelegramLinkCode {
        try await client.post("/telegram/link-code")
    }

    @discardableResult
    public func unlinkTelegram() async throws -> Data {
        try await client.send(.post, "/telegram/unlink")
    }

    @discardableResult
    public func setupTelegramWebhook() async throws -> Data {
        try await client.send(.post, "/telegram/setup")
    }

    @discardableResult
    public func removeTelegramWebhook() async throws -> Data {
        try await client.send(.post, "/telegram/remove-webhook")
    }

    public func digest() async throws -> DigestSettings {
        try await client.get("/digest")
    }

    @discardableResult
    public func updateDigest(_ patch: DigestPatch) async throws -> Data {
        try await client.send(.patch, "/digest", body: patch)
    }

    @discardableResult
    public func sendDigestNow() async throws -> Data {
        try await client.send(.post, "/digest/send-now")
    }

    // MARK: - Audit

    public func audit(limit: Int = 50, offset: Int = 0, siteID: Int? = nil) async throws -> AuditResponse {
        var query = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset))
        ]
        if let siteID { query.append(URLQueryItem(name: "siteId", value: String(siteID))) }
        return try await client.get("/audit", query: query)
    }

    // MARK: - Users

    public func users() async throws -> [User] {
        try await client.get("/users", as: UsersResponse.self).users
    }

    @discardableResult
    public func createUser(_ draft: UserDraft) async throws -> Data {
        try await client.send(.post, "/users", body: draft)
    }

    @discardableResult
    public func updateUser(id: Int, _ patch: UserPatch) async throws -> Data {
        try await client.send(.patch, "/users/\(id)", body: patch)
    }

    @discardableResult
    public func deleteUser(id: Int) async throws -> Data {
        try await client.send(.delete, "/users/\(id)")
    }

    public func userSites(id: Int) async throws -> [Int] {
        try await client.get("/users/\(id)/sites", as: UserSitesResponse.self).siteIds
    }

    @discardableResult
    public func setUserSites(id: Int, siteIDs: [Int]) async throws -> Data {
        struct Body: Encodable, Sendable { var siteIds: [Int] }
        return try await client.send(.put, "/users/\(id)/sites", body: Body(siteIds: siteIDs))
    }

    // MARK: - Settings, password, 2FA, tokens

    public func settings() async throws -> JSONValue {
        try await client.get("/settings", as: JSONValue.self)
    }

    @discardableResult
    public func changePassword(old: String, new: String) async throws -> Data {
        try await client.send(.post, "/settings/change-password",
                              body: ChangePasswordRequest(oldPassword: old, newPassword: new))
    }

    public func twoFactorSetup() async throws -> TwoFactorSetup {
        try await client.get("/auth/2fa/setup")
    }

    @discardableResult
    public func enableTwoFactor(code: String) async throws -> Data {
        struct Body: Encodable, Sendable { var totpCode: String }
        return try await client.send(.post, "/auth/2fa/enable", body: Body(totpCode: code))
    }

    @discardableResult
    public func disableTwoFactor() async throws -> Data {
        try await client.send(.delete, "/auth/2fa")
    }

    public func createToken(name: String, expiresInDays: Int?) async throws -> CreatedToken {
        try await client.post("/tokens", body: CreateTokenRequest(name: name, expiresInDays: expiresInDays))
    }

    @discardableResult
    public func revokeToken(id: Int) async throws -> Data {
        try await client.send(.delete, "/tokens/\(id)")
    }
}
