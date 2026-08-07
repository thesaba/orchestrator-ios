import Foundation

// MARK: - Mutating calls
//
// Everything in this file changes server state on a **production** panel. Two rules:
//
//   1. No view calls these without an explicit user gesture plus a confirmation dialog
//      for anything destructive (deploy, rollback, void, delete, worker stop).
//   2. Every signature below was read off the panel's own React client
//      (tools/probe-web-bundle.sh -> tools/bundle.js), not guessed. Anything still
//      unverified is marked `ASSUMPTION`.

extension OrchestratorAPI {

    // MARK: Deploy

    func deployPending(siteID: Int) async throws -> DeployPending {
        try await client.get("/sites/\(siteID)/deploy/pending")
    }

    /// `POST /sites/:id/deploy?ref=<branch|tag|sha>&skipTests=1`
    ///
    /// Options travel as **query parameters, not a body** — and there is no "comment"
    /// field at all. Omitting `ref` makes the server use the site's configured branch.
    @discardableResult
    func startDeploy(siteID: Int, ref: String? = nil, skipTests: Bool = false) async throws -> Data {
        var query: [URLQueryItem] = []
        if skipTests { query.append(URLQueryItem(name: "skipTests", value: "1")) }
        if let ref, !ref.trimmingCharacters(in: .whitespaces).isEmpty {
            query.append(URLQueryItem(name: "ref", value: ref))
        }
        return try await client.send(.post, "/sites/\(siteID)/deploy", query: query)
    }

    @discardableResult
    func cancelDeploy(siteID: Int) async throws -> Data {
        try await client.send(.post, "/sites/\(siteID)/deploy/cancel")
    }

    func deployStream(siteID: Int) -> AsyncThrowingStream<SSEEvent, Error> {
        client.events("/sites/\(siteID)/deploy/stream")
    }

    func releases(siteID: Int) async throws -> ReleasesResponse {
        try await client.get("/sites/\(siteID)/releases")
    }

    struct RollbackRequest: Encodable, Sendable {
        var release: String
    }

    /// `{ release: "20260727214434" }` — the `name` from `/releases`.
    @discardableResult
    func rollback(siteID: Int, release: String) async throws -> Data {
        try await client.send(.post, "/sites/\(siteID)/rollback", body: RollbackRequest(release: release))
    }

    @discardableResult
    func redeploy(siteID: Int, deploymentID: Int) async throws -> Data {
        try await client.send(.post, "/sites/\(siteID)/deployments/\(deploymentID)/redeploy")
    }

    func testStats(siteID: Int) async throws -> TestStats {
        try await client.get("/sites/\(siteID)/test-stats")
    }

    // MARK: Maintenance

    struct MaintenanceRequest: Encodable, Sendable {
        /// Laravel's own vocabulary: `php artisan down` / `php artisan up`.
        var action: String
        /// Optional bypass secret, forwarded to `artisan down --secret=`.
        var secret: String?
    }

    func maintenance(siteID: Int) async throws -> MaintenanceState {
        try await client.get("/sites/\(siteID)/maintenance")
    }

    /// `POST /sites/:id/maintenance` with `{ action, secret? }` — not `{ enabled }`.
    /// ASSUMPTION: the action strings are `"down"` and `"up"`; the panel's client only
    /// reveals the key name, not its values.
    @discardableResult
    func setMaintenance(siteID: Int, enabled: Bool, secret: String? = nil) async throws -> Data {
        try await client.send(
            .post,
            "/sites/\(siteID)/maintenance",
            body: MaintenanceRequest(action: enabled ? "down" : "up",
                                     secret: (secret?.isEmpty ?? true) ? nil : secret)
        )
    }

    // MARK: Workers (Supervisor)

    func supervisorConfig(siteID: Int) async throws -> FileContents {
        try await client.get("/sites/\(siteID)/supervisor")
    }

    func supervisorStatus(siteID: Int) async throws -> SupervisorStatus {
        try await client.get("/sites/\(siteID)/supervisor/status")
    }

    enum SupervisorAction: String, Sendable, CaseIterable {
        case start, stop, restart

        var title: String { rawValue.capitalized }

        var isDestructive: Bool { self == .stop }
    }

    struct SupervisorControlRequest: Encodable, Sendable {
        var action: String
    }

    /// `POST /sites/:id/supervisor/control` with `{ action }`.
    /// The panel has **no per-process control** — the action always applies to every
    /// worker of the site, so the UI must not pretend otherwise.
    @discardableResult
    func controlSupervisor(siteID: Int, action: SupervisorAction) async throws -> Data {
        try await client.send(
            .post,
            "/sites/\(siteID)/supervisor/control",
            body: SupervisorControlRequest(action: action.rawValue)
        )
    }

    struct SupervisorConfigRequest: Encodable, Sendable {
        var content: String
    }

    @discardableResult
    func saveSupervisorConfig(siteID: Int, content: String) async throws -> Data {
        try await client.send(.put, "/sites/\(siteID)/supervisor", body: SupervisorConfigRequest(content: content))
    }

    // MARK: Queue

    func queueStats(siteID: Int) async throws -> QueueStats {
        try await client.get("/sites/\(siteID)/queue/stats")
    }

    func failedJobs(siteID: Int) async throws -> [FailedJob] {
        try await client.get("/sites/\(siteID)/failed-jobs", as: FailedJobsResponse.self).jobs
    }

    @discardableResult
    func retryFailedJob(siteID: Int, jobID: String) async throws -> Data {
        try await client.send(.post, "/sites/\(siteID)/failed-jobs/\(APIPath.segment(jobID))/retry")
    }

    @discardableResult
    func retryAllFailedJobs(siteID: Int) async throws -> Data {
        try await client.send(.post, "/sites/\(siteID)/failed-jobs/retry-all")
    }

    @discardableResult
    func deleteFailedJob(siteID: Int, jobID: String) async throws -> Data {
        try await client.send(.delete, "/sites/\(siteID)/failed-jobs/\(APIPath.segment(jobID))")
    }

    @discardableResult
    func deleteAllFailedJobs(siteID: Int) async throws -> Data {
        try await client.send(.delete, "/sites/\(siteID)/failed-jobs")
    }

    // MARK: Artisan

    func artisanCommands(siteID: Int) async throws -> [ArtisanCommand] {
        try await client.get("/sites/\(siteID)/artisan/commands", as: ArtisanCommandsResponse.self).commands
    }

    struct ArtisanRunRequest: Encodable, Sendable {
        var command: String
    }

    /// `{ command: "cache:clear" }`. Output arrives on `/artisan/stream`.
    @discardableResult
    func runArtisan(siteID: Int, command: String) async throws -> Data {
        try await client.send(.post, "/sites/\(siteID)/artisan/run", body: ArtisanRunRequest(command: command))
    }

    func artisanStream(siteID: Int) -> AsyncThrowingStream<SSEEvent, Error> {
        client.events("/sites/\(siteID)/artisan/stream")
    }

    // MARK: Billing

    func invoices() async throws -> [Invoice] {
        try await client.get("/billing/invoices")
    }

    func overdueInvoices() async throws -> [Invoice] {
        try await client.get("/billing/invoices/overdue")
    }

    func billingClients() async throws -> [BillingClient] {
        try await client.get("/billing/clients")
    }

    func subscriptions() async throws -> [Subscription] {
        try await client.get("/billing/subscriptions")
    }

    func profitability() async throws -> [ProfitabilityRow] {
        try await client.get("/billing/profitability")
    }

    func enforcementMode() async throws -> EnforcementMode {
        try await client.get("/billing/enforcement")
    }

    /// `PUT { mode: "off"|"dry_run"|"on" }`.
    @discardableResult
    func setEnforcementMode(_ mode: EnforcementMode.Known) async throws -> Data {
        try await client.send(.put, "/billing/enforcement", body: EnforcementMode(mode: mode.rawValue))
    }

    struct InvoicePaymentRequest: Encodable, Sendable {
        /// A decimal **string in major units** — "50.00", not 5000. This is the one
        /// place in the billing API where the amount is not minor units; the panel
        /// sends the text straight out of its input field.
        var amount: String
        /// "cash" is what the panel defaults to.
        var method: String
        var reference: String?
        var note: String?
    }

    struct InvoicePaymentResponse: Decodable, Sendable {
        /// True when paying this invoice lifted a billing suspension.
        var restored: Bool?
    }

    enum PaymentMethod: String, CaseIterable, Identifiable, Sendable {
        case cash, bank, card, other

        var id: String { rawValue }
        var title: String {
            switch self {
            case .cash:  return "Cash"
            case .bank:  return "Bank transfer"
            case .card:  return "Card"
            case .other: return "Other"
            }
        }
    }

    /// `POST /billing/invoices/:id/pay` with `{ amount, method, reference?, note? }`.
    /// Paying less than the balance records a partial payment.
    @discardableResult
    func payInvoice(_ invoiceID: Int,
                    amountMinorUnits: Int,
                    method: PaymentMethod = .cash,
                    reference: String? = nil,
                    note: String? = nil) async throws -> InvoicePaymentResponse {
        let major = String(format: "%.2f", Double(amountMinorUnits) / 100)
        return try await client.post(
            "/billing/invoices/\(invoiceID)/pay",
            body: InvoicePaymentRequest(
                amount: major,
                method: method.rawValue,
                reference: (reference?.isEmpty ?? true) ? nil : reference,
                note: (note?.isEmpty ?? true) ? nil : note
            )
        )
    }

    /// The panel sends a literal `{}` here; Fastify rejects a POST that declares
    /// `Content-Type: application/json` with no body, so send the empty object.
    @discardableResult
    func voidInvoice(_ invoiceID: Int) async throws -> Data {
        try await client.send(.post, "/billing/invoices/\(invoiceID)/void", body: EmptyBody())
    }

    // MARK: Notifications

    @discardableResult
    func markNotificationRead(_ id: Int) async throws -> Data {
        try await client.send(.post, "/notifications/\(id)/read")
    }

    @discardableResult
    func markAllNotificationsRead() async throws -> Data {
        try await client.send(.post, "/notifications/read-all")
    }

    @discardableResult
    func deleteNotification(_ id: Int) async throws -> Data {
        try await client.send(.delete, "/notifications/\(id)")
    }

    @discardableResult
    func clearNotifications() async throws -> Data {
        try await client.send(.delete, "/notifications")
    }
}
