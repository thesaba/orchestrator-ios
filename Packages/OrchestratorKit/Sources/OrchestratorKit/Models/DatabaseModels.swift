import Foundation

/// `GET /api/sites/:id/database/backups`
public struct BackupsResponse: Decodable, Sendable {
    public var backups: [DatabaseBackup]
}

/// The array was empty when surveyed, so field names are read defensively.
public struct DatabaseBackup: Decodable, Sendable, Hashable, Identifiable {
    public var name: String
    public var size: Int?
    public var createdAt: Date?

    public var id: String { name }

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(JSONValue.self)
        if case .string(let text) = value {
            name = text
            return
        }
        name = value["name"]?.stringValue ?? value["filename"]?.stringValue ?? value["file"]?.stringValue ?? "backup"
        size = (value["sizeBytes"] ?? value["size"] ?? value["bytes"])?.intValue
        createdAt = (value["createdAt"] ?? value["created_at"] ?? value["modified"] ?? value["date"])?
            .stringValue.flatMap(DateParsing.parse)
    }

    public var sizeLabel: String { Bytes.string(size) }
}

/// `GET /api/sites/:id/database/backup-schedule`
public struct BackupSchedule: Decodable, Sendable, Hashable {
    public var active: Bool
    public var hour: Int?
    public var minute: Int?
    /// `"*"` = every day, otherwise comma-separated weekday indices (`"1,3,5"`).
    public var days: String?
    public var cronPath: String?

    public var timeLabel: String {
        String(format: "%02d:%02d", hour ?? 0, minute ?? 0)
    }

    public var selectedWeekdays: Set<Int> {
        guard let days, days != "*" else { return Set(0...6) }
        return Set(days.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) })
    }

    public var daysLabel: String {
        guard let days, days != "*" else { return "Every day" }
        let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let picked = selectedWeekdays.sorted().compactMap { names.indices.contains($0) ? names[$0] : nil }
        return picked.isEmpty ? "Every day" : picked.joined(separator: ", ")
    }

    /// Encodes a weekday set back into the `days` string the API expects.
    public static func daysString(from weekdays: Set<Int>) -> String {
        if weekdays.count >= 7 || weekdays.isEmpty { return "*" }
        return weekdays.sorted().map(String.init).joined(separator: ",")
    }
}

/// `GET /api/sites/:id/database/backup/s3`
public struct S3Backups: Decodable, Sendable {
    public var files: [DatabaseBackup]
    public var configured: Bool
}

/// `GET /api/sites/:id/databases`
public struct DatabasesResponse: Decodable, Sendable {
    public var databases: [SiteDatabase]
}

public struct SiteDatabase: Decodable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var siteId: Int?
    public var dbName: String
    public var dbUser: String?
    public var isPrimary: Bool
    public var createdAt: Date?
}

/// `POST /api/sites/:id/databases/:dbId/query` — the shape depends on the statement, so
/// this normalises "rows + columns" out of whatever comes back.
public struct QueryResult: Decodable, Sendable {
    public var columns: [String]
    public var rows: [[String]]
    public var affectedRows: Int?
    public var message: String?
    public var durationMs: Int?
    /// The panel returns at most 1000 rows.
    public var truncated: Bool
    public var raw: JSONValue

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(JSONValue.self)
        raw = value

        affectedRows = (value["affectedRows"] ?? value["rowCount"] ?? value["changes"])?.intValue
        message = value["message"]?.stringValue
        durationMs = (value["elapsedMs"] ?? value["durationMs"] ?? value["duration"] ?? value["timeMs"])?.intValue
        truncated = value["truncated"]?.boolValue ?? false

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
                return array.map { $0.isNull ? "NULL" : ($0.stringValue ?? "") }
            }
            return [row.stringValue ?? ""]
        }

        columns = resolvedColumns
        rows = resolvedRows
    }

    public var isEmpty: Bool { rows.isEmpty && columns.isEmpty }
}
