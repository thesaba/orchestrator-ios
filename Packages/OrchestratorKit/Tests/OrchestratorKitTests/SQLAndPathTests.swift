import Foundation
import Testing
@testable import OrchestratorKit

@Suite("SQL console and file paths")
struct SQLAndPathTests {
    @Test func classifiesReadsAndWrites() {
        #expect(SQLStatement("select * from users").kind == .read)
        #expect(SQLStatement("  -- count\nSHOW TABLES;").kind == .read)
        #expect(SQLStatement("WITH t AS (SELECT 1) SELECT * FROM t").kind == .read)
        #expect(SQLStatement("explain select 1").kind == .read)
        #expect(SQLStatement("UPDATE invoices SET status='paid' WHERE id=4").kind == .write(verb: "UPDATE"))
        #expect(SQLStatement("/* fix */ delete from `sessions`").kind == .write(verb: "DELETE"))
        #expect(SQLStatement("DROP TABLE users").kind == .unsupported(verb: "DROP"))
    }

    @Test func readsTableAndMissingWhere() {
        let update = SQLStatement("UPDATE invoices SET status = 'paid' WHERE id = 4")
        #expect(update.table == "invoices")
        #expect(!update.affectsEveryRow)
        let wipe = SQLStatement("delete from `sessions`")
        #expect(wipe.table == "sessions")
        #expect(wipe.affectsEveryRow)
        #expect(SQLStatement("INSERT INTO jobs (queue) VALUES ('a;b')").table == "jobs")
        #expect(!SQLStatement("INSERT INTO jobs (queue) VALUES ('a;b');").isMultiple)
        #expect(SQLStatement("select 1; select 2").isMultiple)
    }

    @Test func queryResultDecodesPanelShape() throws {
        let json = #"{"columns":["id","email","deleted_at"],"rows":[[1,"a@b.ge",null],[2,"c@d.ge","2026-01-01"]],"rowCount":2,"truncated":false,"elapsedMs":18}"#
        let result = try Fixtures.decode(QueryResult.self, json)
        #expect(result.columns == ["id", "email", "deleted_at"])
        #expect(result.rows[0] == ["1", "a@b.ge", "NULL"])
        #expect(result.durationMs == 18)
        #expect(!result.truncated)
    }

    @Test func backupSizeComesFromSizeBytes() throws {
        let json = #"{"backups":[{"name":"db-2026-11-25.sql.gz","sizeBytes":1048576,"createdAt":"2026-11-25T02:00:00.000Z"}]}"#
        let backup = try Fixtures.decode(BackupsResponse.self, json).backups[0]
        #expect(backup.size == 1_048_576)
        #expect(backup.createdAt != nil)
    }

    @Test func errorMessageIncludesDetails() {
        let data = Data(#"{"error":"Query failed","details":"Unknown column 'x'","code":"ER_BAD_FIELD_ERROR"}"#.utf8)
        #expect(APIClient.errorMessage(from: data) == "Query failed: Unknown column 'x'")
        #expect(APIClient.errorMessage(from: Data(#"{"error":"Site not found"}"#.utf8)) == "Site not found")
    }

    @Test func sitePaths() {
        #expect(SitePath.join("/", "current") == "/current")
        #expect(SitePath.join("/current/", "config") == "/current/config")
        #expect(SitePath.parent(of: "/current/config") == "/current")
        #expect(SitePath.parent(of: "/current") == "/")
        #expect(SitePath.breadcrumbs("/current/config").map(\.path) == ["/current", "/current/config"])
        #expect(SitePath.isValidName("app.php"))
        #expect(!SitePath.isValidName("../etc"))
        #expect(!SitePath.isValidName(" x"))
    }
}
