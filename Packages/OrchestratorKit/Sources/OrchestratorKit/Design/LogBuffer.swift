import Foundation
import Observation

public struct LogLine: Identifiable, Hashable, Sendable {
    public let id: Int
    public let text: String

    public var tone: StatusTone? {
        let lower = text.lowercased()
        if lower.contains("error") || lower.contains("failed") || lower.contains("fatal") { return .critical }
        if lower.contains("warning") || lower.contains("warn") { return .warning }
        if lower.contains("success") || lower.contains("done") || lower.contains("✔") { return .good }
        return nil
    }
}

/// Accumulates streamed output. Kept separate from the views so any feature can own one.
@MainActor
@Observable
public final class LogBuffer {
    public private(set) var lines: [LogLine] = []
    private var nextID = 0

    /// Deploy logs can run to hundreds of thousands of characters; cap what we keep in memory.
    public var limit = 5_000

    public init() {}

    public func append(_ text: String) {
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let clean = ANSI.strip(String(raw))
            lines.append(LogLine(id: nextID, text: clean))
            nextID += 1
        }
        if lines.count > limit {
            lines.removeFirst(lines.count - limit)
        }
    }

    public func replace(with text: String) {
        lines.removeAll()
        nextID = 0
        append(text)
    }

    public func clear() {
        lines.removeAll()
        nextID = 0
    }

    public var plainText: String { lines.map(\.text).joined(separator: "\n") }
}

public enum ANSI {
    private static let pattern = try? NSRegularExpression(pattern: "\u{001B}\\[[0-9;?]*[A-Za-z]")

    /// Deploy output comes from real shell tools, so it carries colour escapes.
    public static func strip(_ text: String) -> String {
        guard let pattern else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return pattern.stringByReplacingMatches(in: text, range: range, withTemplate: "")
            .replacingOccurrences(of: "\r", with: "")
    }
}
