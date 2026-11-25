import Foundation

extension OrchestratorAPI {

    // MARK: - Backups

    public func databaseBackups(siteID: Int) async throws -> [DatabaseBackup] {
        try await client.get("/sites/\(siteID)/database/backups", as: BackupsResponse.self).backups
    }

    @discardableResult
    public func createDatabaseBackup(siteID: Int) async throws -> Data {
        try await client.send(.post, "/sites/\(siteID)/database/backup")
    }

    @discardableResult
    public func deleteDatabaseBackup(siteID: Int, filename: String) async throws -> Data {
        try await client.send(.delete, "/sites/\(siteID)/database/backups/\(APIPath.segment(filename))")
    }

    @discardableResult
    public func restoreDatabaseBackup(siteID: Int, filename: String) async throws -> Data {
        try await client.send(.post, "/sites/\(siteID)/database/backups/\(APIPath.segment(filename))/restore")
    }

    public func downloadDatabaseBackup(siteID: Int, filename: String) async throws -> (Data, String?) {
        try await client.download("/sites/\(siteID)/database/backups/\(APIPath.segment(filename))")
    }

    // MARK: - Schedule

    public func backupSchedule(siteID: Int) async throws -> BackupSchedule {
        try await client.get("/sites/\(siteID)/database/backup-schedule")
    }

    public struct BackupScheduleRequest: Encodable, Sendable {
        public var hour: Int
        public var minute: Int
        /// `"*"` for every day, otherwise comma-separated weekday indices — `"1,3,5"`.
        public var days: String

        public init(hour: Int, minute: Int, days: String) {
            self.hour = hour
            self.minute = minute
            self.days = days
        }
    }

    @discardableResult
    public func enableBackupSchedule(siteID: Int, hour: Int, minute: Int, days: String) async throws -> Data {
        try await client.send(
            .put,
            "/sites/\(siteID)/database/backup-schedule",
            body: BackupScheduleRequest(hour: hour, minute: minute, days: days)
        )
    }

    @discardableResult
    public func disableBackupSchedule(siteID: Int) async throws -> Data {
        try await client.send(.delete, "/sites/\(siteID)/database/backup-schedule")
    }

    // MARK: - Off-site copies

    public func s3Backups(siteID: Int) async throws -> S3Backups {
        try await client.get("/sites/\(siteID)/database/backup/s3")
    }

    @discardableResult
    public func uploadBackupToS3(siteID: Int, filename: String) async throws -> Data {
        try await client.send(.post, "/sites/\(siteID)/database/backup/s3/\(APIPath.segment(filename))")
    }

    @discardableResult
    public func deleteS3Backup(siteID: Int, filename: String) async throws -> Data {
        try await client.send(.delete, "/sites/\(siteID)/database/backup/s3/\(APIPath.segment(filename))")
    }

    // MARK: - Databases

    public func databases(siteID: Int) async throws -> [SiteDatabase] {
        try await client.get("/sites/\(siteID)/databases", as: DatabasesResponse.self).databases
    }

    @discardableResult
    public func deleteDatabase(siteID: Int, databaseID: Int) async throws -> Data {
        try await client.send(.delete, "/sites/\(siteID)/databases/\(databaseID)")
    }

    public struct SQLRequest: Encodable, Sendable {
        public var sql: String

        public init(sql: String) {
            self.sql = sql
        }
    }

    /// `POST { sql }`. The response shape varies by statement kind, so it is decoded
    /// leniently and rendered from whatever comes back.
    public func runQuery(siteID: Int, databaseID: Int, sql: String) async throws -> QueryResult {
        try await client.post("/sites/\(siteID)/databases/\(databaseID)/query", body: SQLRequest(sql: sql))
    }

    /// Opens a phpMyAdmin session; the response carries a URL to hand to Safari.
    public func phpMyAdminSession(siteID: Int, databaseID: Int) async throws -> JSONValue {
        try await client.post("/sites/\(siteID)/databases/\(databaseID)/pma-session", as: JSONValue.self)
    }
}
