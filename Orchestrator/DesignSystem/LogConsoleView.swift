import SwiftUI

struct LogLine: Identifiable, Hashable, Sendable {
    let id: Int
    let text: String

    var tone: StatusTone? {
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
final class LogBuffer {
    private(set) var lines: [LogLine] = []
    private var nextID = 0

    /// Deploy logs can run to hundreds of thousands of characters; cap what we keep in memory.
    var limit = 5_000

    func append(_ text: String) {
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let clean = ANSI.strip(String(raw))
            lines.append(LogLine(id: nextID, text: clean))
            nextID += 1
        }
        if lines.count > limit {
            lines.removeFirst(lines.count - limit)
        }
    }

    func replace(with text: String) {
        lines.removeAll()
        nextID = 0
        append(text)
    }

    func clear() {
        lines.removeAll()
        nextID = 0
    }

    var plainText: String { lines.map(\.text).joined(separator: "\n") }
}

enum ANSI {
    private static let pattern = try? NSRegularExpression(pattern: "\u{001B}\\[[0-9;?]*[A-Za-z]")

    /// Deploy output comes from real shell tools, so it carries colour escapes.
    static func strip(_ text: String) -> String {
        guard let pattern else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return pattern.stringByReplacingMatches(in: text, range: range, withTemplate: "")
            .replacingOccurrences(of: "\r", with: "")
    }
}

struct LogConsoleView: View {
    var lines: [LogLine]
    var isStreaming: Bool = false
    var autoScroll: Bool = true

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(lines) { line in
                        Text(line.text.isEmpty ? " " : line.text)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(line.tone?.color ?? .primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(line.id)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(bottomAnchor)
                }
                .padding(10)
            }
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .onChange(of: lines.count) {
                guard autoScroll else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(bottomAnchor, anchor: .bottom)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isStreaming {
                    HStack(spacing: 5) {
                        ProgressView().controlSize(.mini)
                        Text("streaming")
                            .font(.caption2)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.regularMaterial, in: Capsule())
                    .padding(8)
                }
            }
        }
    }

    private var bottomAnchor: String { "log-bottom-anchor" }
}
