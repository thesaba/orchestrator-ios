import Foundation

/// Typed answers for the actions the Mac app runs. The writes themselves are the iOS app's
/// verified calls (`startDeploy`, `rollback`, `setMaintenance`); these only decode the reply.
extension OrchestratorAPI {
    /// `POST /sites/:id/deploy?ref=` — query parameters only, no body.
    public func requestDeploy(siteID: Int, ref: String? = nil) async throws -> DeployStartResponse {
        let data = try await startDeploy(siteID: siteID, ref: ref)
        return try APIClient.decoder.decode(DeployStartResponse.self, from: data)
    }

    /// `POST /sites/:id/rollback { release }` — the release is a 14-digit directory name.
    public func requestRollback(siteID: Int, release: String) async throws -> DeployStartResponse {
        let data = try await rollback(siteID: siteID, release: release)
        return try APIClient.decoder.decode(DeployStartResponse.self, from: data)
    }

    /// `POST /sites/:id/maintenance { action: "down" | "up" }` — answers when artisan is done.
    public func requestMaintenance(siteID: Int, enabled: Bool) async throws -> MaintenanceResult {
        let data = try await setMaintenance(siteID: siteID, enabled: enabled)
        return try APIClient.decoder.decode(MaintenanceResult.self, from: data)
    }

    /// `GET /sites/:id/branches` — `git ls-remote --heads` on the server; read-only. Empty when
    /// the repository is private and no token is stored.
    public func branches(siteID: Int) async throws -> [String] {
        try await client.get("/sites/\(siteID)/branches", as: BranchesResponse.self).branches
    }

    /// `GET /sites/:id` with up to 20 deployments and their logs. Heavy; fetch on demand.
    public func siteListing(id: Int) async throws -> SiteListing {
        try await client.get("/sites/\(id)")
    }

    /// `GET /ai/explain-deploy/:id` — a stored diagnosis, without asking the AI.
    public func storedDeployExplanation(deploymentID: Int) async throws -> DeployExplanation {
        try await client.get("/ai/explain-deploy/\(deploymentID)")
    }

    /// `POST /ai/explain-deploy/:id[?force=1]` — diagnoses the deploy from its log. Changes
    /// nothing on the site; returns the stored answer unless `force`.
    public func explainDeployment(deploymentID: Int, force: Bool = false) async throws -> DeployExplanation {
        let query = force ? [URLQueryItem(name: "force", value: "1")] : []
        return try await client.post("/ai/explain-deploy/\(deploymentID)", query: query)
    }
}
