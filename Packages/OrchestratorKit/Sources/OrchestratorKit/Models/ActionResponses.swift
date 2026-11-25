import Foundation

/// `POST /api/sites/:id/deploy` and `POST /api/sites/:id/rollback`.
///
/// Either `{ started: true, deploymentId }` or, when a deploy already runs for the site,
/// `{ queued: true, message }` (deploy only; rollback answers 409 instead).
public struct DeployStartResponse: Decodable, Sendable, Hashable {
    public var started: Bool
    public var queued: Bool
    public var deploymentId: Int?
    public var message: String?

    public init(started: Bool, queued: Bool = false, deploymentId: Int? = nil, message: String? = nil) {
        self.started = started
        self.queued = queued
        self.deploymentId = deploymentId
        self.message = message
    }
}

/// `GET` (stored only) and `POST` (asks the AI, unless a stored answer exists and `force` is
/// off) `/api/ai/explain-deploy/:deploymentId`.
public struct DeployExplanation: Decodable, Sendable, Hashable {
    /// `nil` from the GET when nothing has been asked yet.
    public var explanation: String?
    public var cached: Bool

    public init(explanation: String?, cached: Bool = false) {
        self.explanation = explanation
        self.cached = cached
    }
}

/// `POST /api/sites/:id/maintenance` — synchronous: `{ ok, action, output }`.
public struct MaintenanceResult: Decodable, Sendable, Hashable {
    public var ok: Bool
    public var action: String?
    public var output: String?
}

/// `GET /api/sites/:id/branches`.
public struct BranchesResponse: Decodable, Sendable {
    public var branches: [String]
}
