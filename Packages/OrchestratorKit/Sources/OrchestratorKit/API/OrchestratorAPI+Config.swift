import Foundation

// Per-site configuration: nginx, .env (+ versions), PHP version, PHP-FPM pool, SSL.
// Bodies marked `ASSUMPTION` were inferred from route names — see tools/probe-web-bundle.sh.

extension OrchestratorAPI {

    /// The three text configs share one response shape, so one enum keeps their paths together.
    public enum ConfigFile: String, CaseIterable, Identifiable, Sendable {
        case env
        case nginx
        case phpfpm

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .env:    return ".env"
            case .nginx:  return "Nginx"
            case .phpfpm: return "PHP-FPM pool"
            }
        }

        public var symbol: String {
            switch self {
            case .env:    return "key.horizontal"
            case .nginx:  return "server.rack"
            case .phpfpm: return "cpu"
            }
        }

        public var path: String {
            switch self {
            case .env:    return "config/env"
            case .nginx:  return "config/nginx"
            case .phpfpm: return "phpfpm"
            }
        }

        /// Saving nginx or php-fpm reloads a service; .env only rewrites a file.
        public var restartWarning: String? {
            switch self {
            case .env:    return "Laravel reads .env on boot — run `config:clear` from Artisan afterwards."
            case .nginx:  return "Saving reloads nginx. A broken config can take the site offline."
            case .phpfpm: return "Saving reloads PHP-FPM. Active requests may be dropped."
            }
        }
    }

    public func configFile(_ file: ConfigFile, siteID: Int) async throws -> FileContents {
        try await client.get("/sites/\(siteID)/\(file.path)")
    }

    public struct ConfigWriteRequest: Encodable, Sendable {
        public var content: String

        public init(content: String) {
            self.content = content
        }
    }

    /// `PUT { content: "…" }` for all three files. There is no `note` parameter — the
    /// server writes the .env version-history entry itself.
    @discardableResult
    public func saveConfigFile(_ file: ConfigFile, siteID: Int, content: String) async throws -> Data {
        try await client.send(.put, "/sites/\(siteID)/\(file.path)", body: ConfigWriteRequest(content: content))
    }

    // MARK: - .env versions

    public func envVersions(siteID: Int) async throws -> [EnvVersion] {
        try await client.get("/sites/\(siteID)/config/env/versions", as: EnvVersionsResponse.self).versions
    }

    public func envVersion(siteID: Int, versionID: Int) async throws -> EnvVersion {
        try await client.get("/sites/\(siteID)/config/env/versions/\(versionID)")
    }

    @discardableResult
    public func restoreEnvVersion(siteID: Int, versionID: Int) async throws -> Data {
        try await client.send(.post, "/sites/\(siteID)/config/env/versions/\(versionID)/restore")
    }

    // MARK: - PHP

    public func phpVersions(siteID: Int) async throws -> PHPVersions {
        try await client.get("/sites/\(siteID)/php-versions")
    }

    public struct PHPVersionRequest: Encodable, Sendable {
        public var version: String

        public init(version: String) {
            self.version = version
        }
    }

    /// ASSUMPTION: `{ version: "8.4" }`.
    @discardableResult
    public func setPHPVersion(siteID: Int, version: String) async throws -> Data {
        try await client.send(.post, "/sites/\(siteID)/php-version", body: PHPVersionRequest(version: version))
    }

    // MARK: - SSL

    @discardableResult
    public func issueSSL(siteID: Int) async throws -> Data {
        try await client.send(.post, "/sites/\(siteID)/ssl")
    }

    @discardableResult
    public func renewSSL(siteID: Int) async throws -> Data {
        try await client.send(.post, "/sites/\(siteID)/ssl/renew")
    }

    @discardableResult
    public func removeSSL(siteID: Int) async throws -> Data {
        try await client.send(.delete, "/sites/\(siteID)/ssl")
    }

    public func sslStream(siteID: Int) -> AsyncThrowingStream<SSEEvent, Error> {
        client.events("/sites/\(siteID)/ssl/stream")
    }

    // MARK: - Scheduler / cron

    public func scheduler(siteID: Int) async throws -> SchedulerInfo {
        try await client.get("/sites/\(siteID)/scheduler")
    }

    /// Enabling is `PUT` with a literal `{}`; disabling is `DELETE`. There is no
    /// `{ active: Bool }` payload.
    @discardableResult
    public func setScheduler(siteID: Int, active: Bool) async throws -> Data {
        active
            ? try await client.send(.put, "/sites/\(siteID)/scheduler", body: EmptyBody())
            : try await client.send(.delete, "/sites/\(siteID)/scheduler")
    }

    public func cron(siteID: Int) async throws -> SchedulerInfo {
        try await client.get("/sites/\(siteID)/cron")
    }

    @discardableResult
    public func setCron(siteID: Int, active: Bool) async throws -> Data {
        active
            ? try await client.send(.put, "/sites/\(siteID)/cron", body: EmptyBody())
            : try await client.send(.delete, "/sites/\(siteID)/cron")
    }

    // MARK: - Security / status page

    public func security(siteID: Int) async throws -> SiteSecurity {
        try await client.get("/sites/\(siteID)/security")
    }

    public func statusPage(siteID: Int) async throws -> StatusPageInfo {
        try await client.get("/sites/\(siteID)/status-page")
    }

    public struct StatusPageRequest: Encodable, Sendable {
        public var enabled: Bool

        public init(enabled: Bool) {
            self.enabled = enabled
        }
    }

    @discardableResult
    public func setStatusPage(siteID: Int, enabled: Bool) async throws -> Data {
        try await client.send(.post, "/sites/\(siteID)/status-page", body: StatusPageRequest(enabled: enabled))
    }

    public struct SecurityRequest: Encodable, Sendable {
        public var basicAuth: Bool
        public var basicUser: String?
        public var basicPassword: String?
        public var ipMode: String
        public var ipList: [String]

        public init(basicAuth: Bool, basicUser: String? = nil, basicPassword: String? = nil, ipMode: String, ipList: [String]) {
            self.basicAuth = basicAuth
            self.basicUser = basicUser
            self.basicPassword = basicPassword
            self.ipMode = ipMode
            self.ipList = ipList
        }
    }

    /// `POST { basicAuth, basicUser?, basicPassword?, ipMode, ipList[] }` — returns the
    /// new state, so the caller can replace its model with the response.
    public func updateSecurity(siteID: Int,
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
