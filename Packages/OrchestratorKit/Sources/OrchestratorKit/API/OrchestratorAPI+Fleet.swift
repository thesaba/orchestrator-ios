import Foundation

/// Fleet monitoring (`/api/fleet/*`, admin only) and the Mac app's view of the site list.
/// Read-only: every method here is a GET.
extension OrchestratorAPI {
    public func fleetServers() async throws -> FleetServersResponse {
        try await client.get("/fleet/servers")
    }

    /// - Parameters:
    ///   - active: only alerts that have not resolved yet.
    ///   - limit: 1…500; the panel defaults to 100.
    public func fleetAlerts(active: Bool = true, serverID: Int? = nil, limit: Int? = nil) async throws -> [FleetAlertEvent] {
        var query: [URLQueryItem] = []
        if active { query.append(URLQueryItem(name: "active", value: "1")) }
        if let serverID { query.append(URLQueryItem(name: "serverId", value: String(serverID))) }
        if let limit { query.append(URLQueryItem(name: "limit", value: String(limit))) }
        return try await client.get("/fleet/alerts", query: query, as: FleetAlertsResponse.self).events
    }

    /// `GET /api/sites` decoded with the newest deployment's log.
    ///
    /// Heavy (each site carries its last full deploy log). Poll it on a slow interval only.
    public func siteListings() async throws -> [SiteListing] {
        try await client.get("/sites")
    }
}
