import Foundation

/// What to read from a fleet server's logs: the systemd journal (optionally one unit) or a
/// file under /var/log. Mirrors `validateLogsQuery` in the panel so a bad value is caught
/// before the request. Read-only.
public struct FleetLogsQuery: Sendable, Hashable {
    public enum Source: String, Sendable, Hashable, CaseIterable, Identifiable {
        case journal, file
        public var id: String { rawValue }
        public var title: String { self == .journal ? "Service journal" : "Log file" }
    }

    public static let maxLines = 2000

    public var source: Source
    /// A systemd unit for the journal; empty reads the whole journal.
    public var unit: String
    /// An absolute path under /var/log for a file.
    public var path: String
    public var lines: Int
    /// Only lines containing this text.
    public var grep: String

    public init(source: Source = .journal, unit: String = "", path: String = "/var/log/syslog",
                lines: Int = 200, grep: String = "") {
        self.source = source
        self.unit = unit
        self.path = path
        self.lines = lines
        self.grep = grep
    }

    /// Why the panel would refuse this query, or nil when it is fine.
    public var problem: String? {
        guard (1...Self.maxLines).contains(lines) else { return "Lines must be between 1 and \(Self.maxLines)." }
        if grep.count > 200 || grep.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7f }) {
            return "The filter text is too long or contains control characters."
        }
        switch source {
        case .journal:
            if !unit.isEmpty, !Self.isValidUnit(unit) { return "That is not a valid service name." }
        case .file:
            if !Self.isValidLogPath(path) { return "The log file must be an absolute path under /var/log (no “..”)." }
        }
        return nil
    }

    public func queryItems(follow: Bool) -> [URLQueryItem] {
        var items = [URLQueryItem(name: "source", value: source.rawValue),
                     URLQueryItem(name: "lines", value: String(lines))]
        if follow { items.append(URLQueryItem(name: "follow", value: "1")) }
        if !grep.isEmpty { items.append(URLQueryItem(name: "grep", value: grep)) }
        switch source {
        case .journal: if !unit.isEmpty { items.append(URLQueryItem(name: "unit", value: unit)) }
        case .file:    items.append(URLQueryItem(name: "path", value: path))
        }
        return items
    }

    /// `^[A-Za-z0-9@:._-]{1,128}$`
    public static func isValidUnit(_ unit: String) -> Bool {
        guard (1...128).contains(unit.count) else { return false }
        return unit.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) && $0.isASCII || "@:._-".unicodeScalars.contains($0) }
    }

    /// Under /var/log, no "..", no control characters, a normalised path that names a file.
    public static func isValidLogPath(_ path: String) -> Bool {
        guard (10...512).contains(path.count), path.hasPrefix("/var/log/"), !path.contains(".."), !path.hasSuffix("/") else { return false }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._@:+=,~/-")
        guard path.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
        return !path.contains("//") && !path.contains("/./")
    }

    /// Files most Linux servers have, offered as suggestions.
    public static let commonFiles = [
        "/var/log/syslog", "/var/log/auth.log", "/var/log/kern.log",
        "/var/log/nginx/error.log", "/var/log/nginx/access.log",
        "/var/log/mysql/error.log", "/var/log/redis/redis-server.log"
    ]
}

/// `GET /api/fleet/servers/:id/logs` — a snapshot of the last lines.
public struct FleetLogsSnapshot: Decodable, Sendable {
    public var lines: [String]
    public var status: String?
    public var channel: String?
}

extension OrchestratorAPI {
    /// The last lines, once.
    public func fleetLogs(serverID: Int, query: FleetLogsQuery) async throws -> FleetLogsSnapshot {
        try await client.get("/fleet/servers/\(serverID)/logs", query: query.queryItems(follow: false))
    }

    /// The last lines and, with `follow`, new lines as they are written (up to two hours).
    /// Cancelling the consuming task closes the stream.
    public func fleetLogStream(serverID: Int, query: FleetLogsQuery, follow: Bool) -> AsyncThrowingStream<SSEEvent, Error> {
        client.events("/fleet/servers/\(serverID)/logs/stream", query: query.queryItems(follow: follow))
    }
}
