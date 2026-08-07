import Foundation

extension OrchestratorAPI {

    // MARK: - Backups

    func databaseBackups(siteID: Int) async throws -> [DatabaseBackup] {
        try await client.get("/sites/\(siteID)/database/backups", as: BackupsResponse.self).backups
    }

    @discardableResult
    func createDatabaseBackup(siteID: Int) async throws -> Data {
        try await client.send(.post, "/sites/\(siteID)/database/backup")
    }

    @discardableResult
    func deleteDatabaseBackup(siteID: Int, filename: String) async throws -> Data {
        try await client.send(.delete, "/sites/\(siteID)/database/backups/\(APIPath.segment(filename))")
    }

    @discardableResult
    func restoreDatabaseBackup(siteID: Int, filename: String) async throws -> Data {
        try await client.send(.post, "/sites/\(siteID)/database/backups/\(APIPath.segment(filename))/restore")
    }

    func downloadDatabaseBackup(siteID: Int, filename: String) async throws -> (Data, String?) {
        try await client.download("/sites/\(siteID)/database/backups/\(APIPath.segment(filename))")
    }

    // MARK: - Schedule

    func backupSchedule(siteID: Int) async throws -> BackupSchedule {
        try await client.get("/sites/\(siteID)/database/backup-schedule")
    }

    struct BackupScheduleRequest: Encodable, Sendable {
        var hour: Int
        var minute: Int
        /// `"*"` for every day, otherwise comma-separated weekday indices — `"1,3,5"`.
        var days: String
    }

    @discardableResult
    func enableBackupSchedule(siteID: Int, hour: Int, minute: Int, days: String) async throws -> Data {
        try await client.send(
            .put,
            "/sites/\(siteID)/database/backup-schedule",
            body: BackupScheduleRequest(hour: hour, minute: minute, days: days)
        )
    }

    @discardableResult
    func disableBackupSchedule(siteID: Int) async throws -> Data {
        try await client.send(.delete, "/sites/\(siteID)/database/backup-schedule")
    }

    // MARK: - Off-site copies

    func s3Backups(siteID: Int) async throws -> S3Backups {
        try await client.get("/sites/\(siteID)/database/backup/s3")
    }

    @discardableResult
    func uploadBackupToS3(siteID: Int, filename: String) async throws -> Data {
        try await client.send(.post, "/sites/\(siteID)/database/backup/s3/\(APIPath.segment(filename))")
    }

    @discardableResult
    func deleteS3Backup(siteID: Int, filename: String) async throws -> Data {
        try await client.send(.delete, "/sites/\(siteID)/database/backup/s3/\(APIPath.segment(filename))")
    }

    // MARK: - Databases

    func databases(siteID: Int) async throws -> [SiteDatabase] {
        try await client.get("/sites/\(siteID)/databases", as: DatabasesResponse.self).databases
    }

    @discardableResult
    func deleteDatabase(siteID: Int, databaseID: Int) async throws -> Data {
        try await client.send(.delete, "/sites/\(siteID)/databases/\(databaseID)")
    }

    struct SQLRequest: Encodable, Sendable {
        var sql: String
    }

    /// `POST { sql }`. The response shape varies by statement kind, so it is decoded
    /// leniently and rendered from whatever comes back.
    func runQuery(siteID: Int, databaseID: Int, sql: String) async throws -> QueryResult {
        try await client.post("/sites/\(siteID)/databases/\(databaseID)/query", body: SQLRequest(sql: sql))
    }

    /// Opens a phpMyAdmin session; the response carries a URL to hand to Safari.
    func phpMyAdminSession(siteID: Int, databaseID: Int) async throws -> JSONValue {
        try await client.post("/sites/\(siteID)/databases/\(databaseID)/pma-session", as: JSONValue.self)
    }
}
