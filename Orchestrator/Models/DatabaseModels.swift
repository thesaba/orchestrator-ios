import Foundation

/// `GET /api/sites/:id/database/backups`
struct BackupsResponse: Decodable, Sendable {
    var backups: [DatabaseBackup]
}

/// The array was empty when surveyed, so field names are read defensively.
struct DatabaseBackup: Decodable, Sendable, Hashable, Identifiable {
    var name: String
    var size: Int?
    var createdAt: Date?

    var id: String { name }

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(JSONValue.self)
        if case .string(let text) = value {
            name = text
            return
        }
        name = value["name"]?.stringValue ?? value["filename"]?.stringValue ?? value["file"]?.stringValue ?? "backup"
        size = (value["size"] ?? value["bytes"])?.intValue
        createdAt = (value["createdAt"] ?? value["created_at"] ?? value["modified"] ?? value["date"])?
            .stringValue.flatMap(DateParsing.parse)
    }

    var sizeLabel: String { Bytes.string(size) }
}

/// `GET /api/sites/:id/database/backup-schedule`
struct BackupSchedule: Decodable, Sendable, Hashable {
    var active: Bool
    var hour: Int?
    var minute: Int?
    /// `"*"` = every day, otherwise comma-separated weekday indices (`"1,3,5"`).
    var days: String?
    var cronPath: String?

    var timeLabel: String {
        String(format: "%02d:%02d", hour ?? 0, minute ?? 0)
    }

    var selectedWeekdays: Set<Int> {
        guard let days, days != "*" else { return Set(0...6) }
        return Set(days.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) })
    }

    var daysLabel: String {
        guard let days, days != "*" else { return "Every day" }
        let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let picked = selectedWeekdays.sorted().compactMap { names.indices.contains($0) ? names[$0] : nil }
        return picked.isEmpty ? "Every day" : picked.joined(separator: ", ")
    }

    /// Encodes a weekday set back into the `days` string the API expects.
    static func daysString(from weekdays: Set<Int>) -> String {
        if weekdays.count >= 7 || weekdays.isEmpty { return "*" }
        return weekdays.sorted().map(String.init).joined(separator: ",")
    }
}

/// `GET /api/sites/:id/database/backup/s3`
struct S3Backups: Decodable, Sendable {
    var files: [DatabaseBackup]
    var configured: Bool
}

/// `GET /api/sites/:id/databases`
struct DatabasesResponse: Decodable, Sendable {
    var databases: [SiteDatabase]
}

struct SiteDatabase: Decodable, Sendable, Hashable, Identifiable {
    var id: Int
    var siteId: Int?
    var dbName: String
    var dbUser: String?
    var isPrimary: Bool
    var createdAt: Date?
}

/// `POST /api/sites/:id/databases/:dbId/query` — the shape depends on the statement, so
/// this normalises "rows + columns" out of whatever comes back.
struct QueryResult: Decodable, Sendable {
    var columns: [String]
    var rows: [[String]]
    var affectedRows: Int?
    var message: String?
    var durationMs: Int?
    var raw: JSONValue

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(JSONValue.self)
        raw = value

        affectedRows = (value["affectedRows"] ?? value["rowCount"] ?? value["changes"])?.intValue
        message = value["message"]?.stringValue
        durationMs = (value["durationMs"] ?? value["duration"] ?? value["timeMs"])?.intValue

        let rowsNode = value["rows"] ?? value["results"] ?? value["data"] ?? value
        let rowObjects = rowsNode.arrayValue ?? []

        // Build into locals first — referring to `columns` inside the row closure would
        // capture `self` before every stored property is initialised.
        let resolvedColumns: [String]
        if let declared = (value["columns"] ?? value["fields"])?.arrayValue {
            resolvedColumns = declared.compactMap { $0.stringValue ?? $0["name"]?.stringValue }
        } else {
            // Union of keys, first row's order first so the common case reads naturally.
            var ordered: [String] = []
            for row in rowObjects {
                guard let object = row.objectValue else { continue }
                for key in object.keys where !ordered.contains(key) {
                    ordered.append(key)
                }
            }
            resolvedColumns = ordered
        }

        let resolvedRows: [[String]] = rowObjects.map { row in
            if let object = row.objectValue {
                return resolvedColumns.map { key in
                    guard let cell = object[key] else { return "" }
                    return cell.isNull ? "NULL" : (cell.stringValue ?? "")
                }
            }
            if let array = row.arrayValue {
                return array.map { $0.stringValue ?? "" }
            }
            return [row.stringValue ?? ""]
        }

        columns = resolvedColumns
        rows = resolvedRows
    }

    var isEmpty: Bool { rows.isEmpty && columns.isEmpty }
}
