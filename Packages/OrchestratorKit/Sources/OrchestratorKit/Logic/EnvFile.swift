import Foundation

/// A Laravel `.env` file read for display: its variables in file order, grouped by prefix,
/// with secrets recognised so they can be masked. Pure, so it is unit-tested.
///
/// Only the display is derived here; saving always sends the text exactly as edited.
public struct EnvFile: Sendable, Hashable {
    public struct Entry: Sendable, Hashable, Identifiable {
        public var key: String
        /// Without surrounding quotes.
        public var value: String
        /// 0-based line in the file.
        public var line: Int
        public var isSecret: Bool

        public var id: String { key }

        /// "••••••••" for secrets, the value otherwise.
        public var maskedValue: String {
            guard isSecret else { return value }
            return value.isEmpty ? "" : String(repeating: "•", count: min(max(value.count, 8), 16))
        }
    }

    public struct Group: Sendable, Hashable, Identifiable {
        /// "APP", "DB", "MAIL"; "Other" for keys without a prefix.
        public var name: String
        public var entries: [Entry]

        public var id: String { name }
    }

    public var entries: [Entry]

    public init(_ text: String) {
        var entries: [Entry] = []
        var seen: Set<String> = []
        for (index, raw) in text.components(separatedBy: "\n").enumerated() {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasSuffix("\r") { line.removeLast() }
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            if line.hasPrefix("export ") { line = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, !key.contains(" ") else { continue }
            let value = Self.unquote(String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespaces))
            // A repeated key: the later line wins, as in phpdotenv.
            if seen.contains(key) { entries.removeAll { $0.key == key } }
            seen.insert(key)
            entries.append(Entry(key: key, value: value, line: index, isSecret: Self.isSecret(key: key)))
        }
        self.entries = entries
    }

    /// Entries grouped by the part of the key before the first underscore, in file order.
    /// Prefixes used by a single key go to "Other".
    public var groups: [Group] {
        func prefix(_ key: String) -> String? {
            guard let underscore = key.firstIndex(of: "_"), underscore != key.startIndex else { return nil }
            return String(key[..<underscore])
        }
        var counts: [String: Int] = [:]
        for entry in entries { if let p = prefix(entry.key) { counts[p, default: 0] += 1 } }
        var order: [String] = []
        var byName: [String: [Entry]] = [:]
        for entry in entries {
            let name = prefix(entry.key).flatMap { (counts[$0] ?? 0) > 1 ? $0 : nil } ?? "Other"
            if byName[name] == nil { order.append(name) }
            byName[name, default: []].append(entry)
        }
        // "Other" last.
        order.sort { ($0 == "Other" ? 1 : 0) < ($1 == "Other" ? 1 : 0) }
        return order.map { Group(name: $0, entries: byName[$0] ?? []) }
    }

    public func value(for key: String) -> String? {
        entries.first { $0.key == key }?.value
    }

    // MARK: - Secrets

    private static let secretWords = ["KEY", "SECRET", "PASSWORD", "PASS", "TOKEN", "DSN", "PRIVATE", "SALT", "CREDENTIALS", "AUTH"]
    /// Keys that contain a secret word but hold no secret.
    private static let notSecret: Set<String> = ["APP_KEY_ROTATION", "MAIL_PASSWORD_RESET_URL"]

    /// Names that usually hold credentials, `APP_KEY` and `*_PASSWORD` among them.
    public static func isSecret(key: String) -> Bool {
        let upper = key.uppercased()
        if notSecret.contains(upper) { return false }
        let parts = upper.split(separator: "_").map(String.init)
        return parts.contains { secretWords.contains($0) }
    }

    private static func unquote(_ value: String) -> String {
        var text = value
        if let first = text.first, first == "\"" || first == "'" {
            if let closing = text.dropFirst().firstIndex(of: first) {
                return String(text[text.index(after: text.startIndex)..<closing])
            }
            return String(text.dropFirst())
        }
        // An unquoted value ends at an inline comment.
        if let hash = text.range(of: " #") { text = String(text[..<hash.lowerBound]) }
        return text.trimmingCharacters(in: .whitespaces)
    }
}

/// One difference between two versions of an `.env` file.
public struct EnvChange: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable { case added, removed, changed }
    public var key: String
    public var kind: Kind
    public var isSecret: Bool

    public var id: String { key }

    /// "+ QUEUE_CONNECTION", "− DEBUGBAR", "~ APP_URL" — never the values themselves.
    public var summary: String {
        switch kind {
        case .added:   return "+ \(key)"
        case .removed: return "− \(key)"
        case .changed: return "~ \(key)"
        }
    }

    /// The keys that differ, in the order of the new file, removals last.
    public static func between(_ old: String, _ new: String) -> [EnvChange] {
        let before = EnvFile(old)
        let after = EnvFile(new)
        let oldValues = Dictionary(before.entries.map { ($0.key, $0.value) }, uniquingKeysWith: { _, last in last })
        let newKeys = Set(after.entries.map(\.key))
        var changes: [EnvChange] = []
        for entry in after.entries {
            if let previous = oldValues[entry.key] {
                if previous != entry.value { changes.append(EnvChange(key: entry.key, kind: .changed, isSecret: entry.isSecret)) }
            } else {
                changes.append(EnvChange(key: entry.key, kind: .added, isSecret: entry.isSecret))
            }
        }
        for entry in before.entries where !newKeys.contains(entry.key) {
            changes.append(EnvChange(key: entry.key, kind: .removed, isSecret: entry.isSecret))
        }
        return changes
    }
}
