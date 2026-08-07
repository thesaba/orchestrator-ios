import Foundation

/// `GET /api/sites/:id/config/env/versions`
struct EnvVersionsResponse: Decodable, Sendable {
    var versions: [EnvVersion]
}

struct EnvVersion: Decodable, Sendable, Hashable, Identifiable {
    struct Author: Decodable, Sendable, Hashable {
        var email: String?
    }

    var id: Int
    var note: String?
    var createdAt: Date?
    var createdBy: Author?
    /// Only present on `GET /config/env/versions/:vid`.
    var content: String?

    var authorEmail: String { createdBy?.email ?? "—" }
}

/// `GET /api/sites/:id/php-versions`
struct PHPVersions: Decodable, Sendable, Hashable {
    var current: String?
    var available: [String]
}

/// One entry from `GET /api/sites/:id/files`
struct FileEntry: Decodable, Sendable, Hashable, Identifiable {
    var name: String
    var type: String
    var size: Int?
    var modified: Date?
    var permissions: String?
    var permsDisplay: String?
    var owner: String?
    var group: String?
    var ext: String?
    var mime: String?

    var id: String { name }

    var isDirectory: Bool { type == "dir" }
    var isSymlink: Bool { type == "symlink" }

    var symbol: String {
        if isDirectory { return "folder.fill" }
        if isSymlink { return "arrow.turn.down.right" }
        switch (ext ?? "").lowercased() {
        case "php", "js", "ts", "swift", "py", "rb", "go":       return "chevron.left.forwardslash.chevron.right"
        case "json", "yml", "yaml", "xml", "toml", "ini", "env": return "curlybraces"
        case "md", "txt", "log":                                  return "doc.text"
        case "png", "jpg", "jpeg", "gif", "webp", "svg":          return "photo"
        case "zip", "gz", "tar", "bz2":                           return "doc.zipper"
        case "sql":                                               return "cylinder"
        default:                                                  return "doc"
        }
    }

    var tint: StatusTone {
        if isDirectory { return .info }
        if isSymlink { return .warning }
        return .neutral
    }

    /// Text-ish files can be opened in the built-in editor; anything else only downloads.
    var isEditable: Bool {
        guard !isDirectory else { return false }
        if (mime ?? "").hasPrefix("text/") { return true }
        let textExtensions: Set<String> = [
            "php", "js", "mjs", "cjs", "ts", "tsx", "jsx", "css", "scss", "html", "htm",
            "json", "yml", "yaml", "xml", "toml", "ini", "conf", "env", "md", "txt",
            "log", "sh", "bash", "sql", "lock", "gitignore", "editorconfig", ""
        ]
        return textExtensions.contains((ext ?? "").lowercased()) && (size ?? 0) < 2_000_000
    }
}

/// `GET /api/sites/:id/files?path=…`
struct FileListing: Decodable, Sendable {
    var entries: [FileEntry]
    var path: String
    var rootPath: String?
}

/// `GET /api/sites/:id/files/read?path=…`
struct FileReadResponse: Decodable, Sendable {
    var content: String
    var path: String?
    var truncated: Bool?

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(JSONValue.self)
        content = value["content"]?.stringValue ?? value["body"]?.stringValue ?? ""
        path = value["path"]?.stringValue
        truncated = value["truncated"]?.boolValue
    }
}

/// `GET /api/sites/:id/files/properties?path=…` — shape unconfirmed, read defensively.
struct FileProperties: Decodable, Sendable {
    var path: String?
    var size: Int?
    var permissions: String?
    var owner: String?
    var group: String?
    var modified: Date?
    var mime: String?
    var lines: Int?
    var raw: JSONValue

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(JSONValue.self)
        raw = value
        path = value["path"]?.stringValue
        size = value["size"]?.intValue
        permissions = value["permissions"]?.stringValue ?? value["permsDisplay"]?.stringValue
        owner = value["owner"]?.stringValue
        group = value["group"]?.stringValue
        modified = value["modified"]?.stringValue.flatMap(DateParsing.parse)
        mime = value["mime"]?.stringValue
        lines = value["lines"]?.intValue
    }
}

/// `GET /api/sites/:id/security`
struct SiteSecurity: Decodable, Sendable {
    var basicAuth: Bool
    var basicUser: String?
    var hasPassword: Bool
    var ipMode: String?
    var ipList: [String]
}

/// `GET /api/sites/:id/status-page`
struct StatusPageInfo: Decodable, Sendable {
    var enabled: Bool
    var token: String?
    var url: String?
}

/// `GET /api/sites/:id/scheduler` and `GET /api/sites/:id/cron`
struct SchedulerInfo: Decodable, Sendable {
    var active: Bool
    var cronPath: String?
    var cronContent: String?
    var content: String?
    var path: String?
    var expected: String?

    var currentContent: String { cronContent ?? content ?? "" }
    var currentPath: String? { cronPath ?? path }
}
