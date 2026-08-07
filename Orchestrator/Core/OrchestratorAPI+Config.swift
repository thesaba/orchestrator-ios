import Foundation

// Per-site configuration: nginx, .env (+ versions), PHP version, PHP-FPM pool, SSL.
// Bodies marked `ASSUMPTION` were inferred from route names — see tools/probe-web-bundle.sh.

extension OrchestratorAPI {

    /// The three text configs share one response shape, so one enum keeps their paths together.
    enum ConfigFile: String, CaseIterable, Identifiable, Sendable {
        case env
        case nginx
        case phpfpm

        var id: String { rawValue }

        var title: String {
            switch self {
            case .env:    return ".env"
            case .nginx:  return "Nginx"
            case .phpfpm: return "PHP-FPM pool"
            }
        }

        var symbol: String {
            switch self {
            case .env:    return "key.horizontal"
            case .nginx:  return "server.rack"
            case .phpfpm: return "cpu"
            }
        }

        var path: String {
            switch self {
            case .env:    return "config/env"
            case .nginx:  return "config/nginx"
            case .phpfpm: return "phpfpm"
            }
        }

        /// Saving nginx or php-fpm reloads a service; .env only rewrites a file.
        var restartWarning: String? {
            switch self {
            case .env:    return "Laravel reads .env on boot — run `config:clear` from Artisan afterwards."
            case .nginx:  return "Saving reloads nginx. A broken config can take the site offline."
            case .phpfpm: return "Saving reloads PHP-FPM. Active requests may be dropped."
            }
        }
    }

    func configFile(_ file: ConfigFile, siteID: Int) async throws -> FileContents {
        try await client.get("/sites/\(siteID)/\(file.path)")
    }

    struct ConfigWriteRequest: Encodable, Sendable {
        var content: String
    }

    /// `PUT { content: "…" }` for all three files. There is no `note` parameter — the
    /// server writes the .env version-history entry itself.
    @discardableResult
    func saveConfigFile(_ file: ConfigFile, siteID: Int, content: String) async throws -> Data {
        try await client.send(.put, "/sites/\(siteID)/\(file.path)", body: ConfigWriteRequest(content: content))
    }

    // MARK: - .env versions

    func envVersions(siteID: Int) async throws -> [EnvVersion] {
        try await client.get("/sites/\(siteID)/config/env/versions", as: EnvVersionsResponse.self).versions
    }

    func envVersion(siteID: Int, versionID: Int) async throws -> EnvVersion {
        try await client.get("/sites/\(siteID)/config/env/versions/\(versionID)")
    }

    @discardableResult
    func restoreEnvVersion(siteID: Int, versionID: Int) async throws -> Data {
        try await client.send(.post, "/sites/\(siteID)/config/env/versions/\(versionID)/restore")
    }

    // MARK: - PHP

    func phpVersions(siteID: Int) async throws -> PHPVersions {
        try await client.get("/sites/\(siteID)/php-versions")
    }

    struct PHPVersionRequest: Encodable, Sendable {
        var version: String
    }

    /// ASSUMPTION: `{ version: "8.4" }`.
    @discardableResult
    func setPHPVersion(siteID: Int, version: String) async throws -> Data {
        try await client.send(.post, "/sites/\(siteID)/php-version", body: PHPVersionRequest(version: version))
    }

    // MARK: - SSL

    @discardableResult
    func issueSSL(siteID: Int) async throws -> Data {
        try await client.send(.post, "/sites/\(siteID)/ssl")
    }

    @discardableResult
    func renewSSL(siteID: Int) async throws -> Data {
        try await client.send(.post, "/sites/\(siteID)/ssl/renew")
    }

    @discardableResult
    func removeSSL(siteID: Int) async throws -> Data {
        try await client.send(.delete, "/sites/\(siteID)/ssl")
    }

    func sslStream(siteID: Int) -> AsyncThrowingStream<SSEEvent, Error> {
        client.events("/sites/\(siteID)/ssl/stream")
    }

    // MARK: - Scheduler / cron

    func scheduler(siteID: Int) async throws -> SchedulerInfo {
        try await client.get("/sites/\(siteID)/scheduler")
    }

    /// Enabling is `PUT` with a literal `{}`; disabling is `DELETE`. There is no
    /// `{ active: Bool }` payload.
    @discardableResult
    func setScheduler(siteID: Int, active: Bool) async throws -> Data {
        active
            ? try await client.send(.put, "/sites/\(siteID)/scheduler", body: EmptyBody())
            : try await client.send(.delete, "/sites/\(siteID)/scheduler")
    }

    func cron(siteID: Int) async throws -> SchedulerInfo {
        try await client.get("/sites/\(siteID)/cron")
    }

    @discardableResult
    func setCron(siteID: Int, active: Bool) async throws -> Data {
        active
            ? try await client.send(.put, "/sites/\(siteID)/cron", body: EmptyBody())
            : try await client.send(.delete, "/sites/\(siteID)/cron")
    }

    // MARK: - Security / status page

    func security(siteID: Int) async throws -> SiteSecurity {
        try await client.get("/sites/\(siteID)/security")
    }

    func statusPage(siteID: Int) async throws -> StatusPageInfo {
        try await client.get("/sites/\(siteID)/status-page")
    }

    struct StatusPageRequest: Encodable, Sendable {
        var enabled: Bool
    }

    @discardableResult
    func setStatusPage(siteID: Int, enabled: Bool) async throws -> Data {
        try await client.send(.post, "/sites/\(siteID)/status-page", body: StatusPageRequest(enabled: enabled))
    }

    struct SecurityRequest: Encodable, Sendable {
        var basicAuth: Bool
        var basicUser: String?
        var basicPassword: String?
        var ipMode: String
        var ipList: [String]
    }

    /// `POST { basicAuth, basicUser?, basicPassword?, ipMode, ipList[] }` — returns the
    /// new state, so the caller can replace its model with the response.
    func updateSecurity(siteID: Int,
                        basicAuth: Bool,
                        basicUser: String?,
                        basicPassword: String?,
                        ipMode: String,
                        ipList: [String]) async throws -> SiteSecurity {
        try await client.post(
            "/sites/\(siteID)/security",
            body: SecurityRequest(
                basicAuth: basicAuth,
                basicUser: (basicUser?.isEmpty ?? true) ? nil : basicUser,
                basicPassword: (basicPassword?.isEmpty ?? true) ? nil : basicPassword,
                ipMode: ipMode,
                ipList: ipList
            )
        )
    }
}
