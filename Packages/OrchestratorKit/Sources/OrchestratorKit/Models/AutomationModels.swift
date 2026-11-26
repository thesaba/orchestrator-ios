import Foundation

/// `GET /api/automation/rules` — when an event happens, act (notify, Telegram, webhook).
public struct AutomationRule: Decodable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var name: String
    /// Event type, `deploy.failed`.
    public var trigger: String
    /// `notify`, `telegram` or `webhook`.
    public var actionType: String
    public var enabled: Bool
    /// Evaluated and logged, but the action is not carried out.
    public var dryRun: Bool
    public var lastFiredAt: Date?
}

struct AutomationRulesResponse: Decodable, Sendable { var rules: [AutomationRule] }

/// `GET /api/automation/webhooks` — outbound webhooks for panel events.
public struct OutboundWebhook: Decodable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var name: String
    public var url: String
    /// Event types; empty means every event.
    public var events: [String]
    public var active: Bool
    public var hasSecret: Bool?
}

struct WebhooksResponse: Decodable, Sendable { var webhooks: [OutboundWebhook] }

extension OrchestratorAPI {
    public func automationRules() async throws -> [AutomationRule] {
        try await client.get("/automation/rules", as: AutomationRulesResponse.self).rules
    }

    public func webhooks() async throws -> [OutboundWebhook] {
        try await client.get("/automation/webhooks", as: WebhooksResponse.self).webhooks
    }
}
