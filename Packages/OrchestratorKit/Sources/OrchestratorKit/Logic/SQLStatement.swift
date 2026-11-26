import Foundation

/// What a SQL statement typed into the console does, so the app knows whether it only reads
/// or changes data, and what to say before it runs. Pure, so it is unit-tested.
public struct SQLStatement: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        /// SELECT, SHOW, DESCRIBE, EXPLAIN, or WITH … SELECT.
        case read
        /// INSERT, UPDATE or DELETE.
        case write(verb: String)
        /// Anything else; the panel refuses it.
        case unsupported(verb: String)
    }

    public var kind: Kind
    /// The table after INSERT INTO / UPDATE / DELETE FROM, when it can be read.
    public var table: String?
    /// An UPDATE or DELETE without WHERE touches every row.
    public var affectsEveryRow: Bool
    /// More than one statement separated by `;`.
    public var isMultiple: Bool

    public var isWrite: Bool {
        if case .write = kind { return true }
        return false
    }

    public init(_ sql: String) {
        let text = Self.stripComments(sql).trimmingCharacters(in: .whitespacesAndNewlines)
        let body = text.hasSuffix(";") ? String(text.dropLast()) : text
        isMultiple = Self.splitOutsideQuotes(body).count > 1
        let words = body.split(whereSeparator: { $0.isWhitespace || $0 == "(" }).map { $0.uppercased() }
        let verb = words.first ?? ""

        switch verb {
        case "SELECT", "SHOW", "DESCRIBE", "DESC", "EXPLAIN":
            kind = .read
        case "WITH":
            if let writer = words.first(where: { ["INSERT", "UPDATE", "DELETE"].contains($0) }) {
                kind = .write(verb: writer)
            } else {
                kind = .read
            }
        case "INSERT", "UPDATE", "DELETE":
            kind = .write(verb: verb)
        default:
            kind = .unsupported(verb: verb)
        }

        var table: String?
        if case .write(let writer) = kind, let index = words.firstIndex(of: writer) {
            let rest = Array(words[(index + 1)...])
            let skip: Set<String> = ["INTO", "FROM", "LOW_PRIORITY", "IGNORE", "QUICK", "DELAYED", "HIGH_PRIORITY"]
            table = rest.first { !skip.contains($0) }.map { name in
                // Keep the original spelling of the table name.
                let original = body.split(whereSeparator: { $0.isWhitespace || $0 == "(" })
                    .first { $0.uppercased() == name }.map(String.init) ?? name
                return original.trimmingCharacters(in: CharacterSet(charactersIn: "`\""))
            }
        }
        self.table = table

        if case .write(let writer) = kind, writer == "UPDATE" || writer == "DELETE" {
            affectsEveryRow = !words.contains("WHERE")
        } else {
            affectsEveryRow = false
        }
    }

    private static func stripComments(_ sql: String) -> String {
        var lines: [String] = []
        for line in sql.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("--") || trimmed.hasPrefix("#") { continue }
            lines.append(line)
        }
        var text = lines.joined(separator: "\n")
        while let start = text.range(of: "/*"), let end = text.range(of: "*/", range: start.upperBound..<text.endIndex) {
            text.removeSubrange(start.lowerBound..<end.upperBound)
        }
        return text
    }

    private static func splitOutsideQuotes(_ text: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var quote: Character?
        for char in text {
            if let open = quote {
                if char == open { quote = nil }
            } else if char == "'" || char == "\"" || char == "`" {
                quote = char
            } else if char == ";" {
                if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { parts.append(current) }
                current = ""
                continue
            }
            current.append(char)
        }
        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { parts.append(current) }
        return parts
    }
}

/// Paths of the file manager, always relative to the site root and starting with "/".
public enum SitePath {
    public static func join(_ directory: String, _ name: String) -> String {
        let base = directory.hasSuffix("/") ? String(directory.dropLast()) : directory
        return (base.isEmpty ? "" : base) + "/" + name
    }

    public static func parent(of path: String) -> String {
        let parts = components(path)
        return parts.count <= 1 ? "/" : "/" + parts.dropLast().joined(separator: "/")
    }

    public static func components(_ path: String) -> [String] {
        path.split(separator: "/").map(String.init).filter { $0 != "." && !$0.isEmpty }
    }

    /// ("current", "/current"), ("config", "/current/config") for "/current/config".
    public static func breadcrumbs(_ path: String) -> [(name: String, path: String)] {
        var result: [(String, String)] = []
        var running = ""
        for part in components(path) {
            running += "/" + part
            result.append((part, running))
        }
        return result
    }

    /// A name a user typed for a new file or folder: no slashes, not "." or "..".
    public static func isValidName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && trimmed != "." && trimmed != ".." && !trimmed.contains("/") && trimmed == name
    }
}
