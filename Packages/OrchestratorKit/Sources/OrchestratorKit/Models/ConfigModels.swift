import Foundation

/// `GET /api/sites/:id/config/env/versions`
public struct EnvVersionsResponse: Decodable, Sendable {
    public var versions: [EnvVersion]
}

public struct EnvVersion: Decodable, Sendable, Hashable, Identifiable {
    public struct Author: Decodable, Sendable, Hashable {
        public var email: String?
    }

    public var id: Int
    public var note: String?
    public var createdAt: Date?
    public var createdBy: Author?
    /// Only present on `GET /config/env/versions/:vid`.
    public var content: String?

    public var authorEmail: String { createdBy?.email ?? "—" }
}

/// `GET /api/sites/:id/php-versions`
public struct PHPVersions: Decodable, Sendable, Hashable {
    public var current: String?
    public var available: [String]
}

/// One entry from `GET /api/sites/:id/files`
public struct FileEntry: Decodable, Sendable, Hashable, Identifiable {
    public var name: String
    public var type: String
    public var size: Int?
    public var modified: Date?
    public var permissions: String?
    public var permsDisplay: String?
    public var owner: String?
    public var group: String?
    public var ext: String?
    public var mime: String?

    public var id: String { name }

    public var isDirectory: Bool { type == "dir" }
    public var isSymlink: Bool { type == "symlink" }

    public var symbol: String {
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

    public var tint: StatusTone {
        if isDirectory { return .info }
        if isSymlink { return .warning }
        return .neutral
    }

    /// Text-ish files can be opened in the built-in editor; anything else only downloads.
    public var isEditable: Bool {
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
public struct FileListing: Decodable, Sendable {
    public var entries: [FileEntry]
    public var path: String
    public var rootPath: String?
}

/// `GET /api/sites/:id/files/read?path=…`
public struct FileReadResponse: Decodable, Sendable {
    public var content: String
    public var path: String?
    public var truncated: Bool?
    /// The content is base64 (images and other binary files).
    public var binary: Bool
    public var mime: String?
    public var size: Int?

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(JSONValue.self)
        content = value["content"]?.stringValue ?? value["body"]?.stringValue ?? ""
        path = value["path"]?.stringValue
        truncated = value["truncated"]?.boolValue
        binary = value["binary"]?.boolValue ?? false
        mime = value["mime"]?.stringValue
        size = value["size"]?.intValue
    }
}

/// `GET /api/sites/:id/files/properties?path=…` — shape unconfirmed, read defensively.
public struct FileProperties: Decodable, Sendable {
    public var path: String?
    public var size: Int?
    public var permissions: String?
    public var owner: String?
    public var group: String?
    public var modified: Date?
    public var mime: String?
    public var lines: Int?
    public var raw: JSONValue

    public init(from decoder: Decoder) throws {
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
public struct SiteSecurity: Decodable, Sendable {
    public var basicAuth: Bool
    public var basicUser: String?
    public var hasPassword: Bool
    public var ipMode: String?
    public var ipList: [String]
}

/// `GET /api/sites/:id/status-page`
public struct StatusPageInfo: Decodable, Sendable {
    public var enabled: Bool
    public var token: String?
    public var url: String?
}

/// `GET /api/sites/:id/scheduler` and `GET /api/sites/:id/cron`
public struct SchedulerInfo: Decodable, Sendable {
    public var active: Bool
    public var cronPath: String?
    public var cronContent: String?
    public var content: String?
    public var path: String?
    public var expected: String?

    public var currentContent: String { cronContent ?? content ?? "" }
    public var currentPath: String? { cronPath ?? path }
}
