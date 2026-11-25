import Foundation

/// How a deploy or command log line is drawn. Ported from the web panel's log console
/// classifier, so both front ends colour the same lines the same way.
public enum LogLineStyle: Sendable, Hashable {
    case error, success, warning, info, step, muted, plain

    /// Splits `[HH:MM:SS] text` into its clock and text.
    public static func split(_ line: String) -> (time: String?, text: String) {
        let substring = Substring(line)
        guard let stamp = DeployLogParser.timestamp(in: substring) else { return (nil, line) }
        let time = String(substring.dropFirst().prefix(8))
        return (time, String(stamp.1))
    }

    public static func classify(_ text: String) -> LogLineStyle {
        let lower = text.lowercased()
        if text.contains(where: { "✓✔√".contains($0) }) { return .success }
        if text.contains(where: { "✗✘×❌".contains($0) }) { return .error }
        if text.contains("⚠") { return .warning }
        if lower.contains(".critical") || lower.contains(".error") || lower.contains(".emergency") { return .error }
        if lower.contains(".warning") || lower.contains(".alert") || lower.contains(".notice") { return .warning }
        if text.hasPrefix("__") { return .muted }
        if isStepHeader(text) { return .step }
        if matchesWord(lower, ["error", "errors", "failed", "failure", "fatal", "exception", "denied", "refused",
                                "cannot", "could not", "not found", "sqlstate", "aborting", "abort", "fail"]) {
            return .error
        }
        if matchesWord(lower, ["warning", "warn", "deprecated", "skipped", "skipping", "notice"]) { return .warning }
        if matchesWord(lower, ["success", "succeeded", "passed", "complete", "completed", "installed", "created", "ok"]) {
            return .success
        }
        return .plain
    }

    /// `[3/8] …` and `=== … ===` lines open a step.
    public static func isStepHeader(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if DeployLogParser.stepHeader(in: Substring(trimmed), startedAt: nil) != nil { return true }
        return trimmed.hasPrefix("==") && trimmed.hasSuffix("==") && trimmed.count > 4
    }

    private static func matchesWord(_ text: String, _ words: [String]) -> Bool {
        words.contains { word in
            var searchRange = text.startIndex..<text.endIndex
            while let range = text.range(of: word, range: searchRange) {
                let before = range.lowerBound == text.startIndex ? nil : text[text.index(before: range.lowerBound)]
                let after = range.upperBound == text.endIndex ? nil : text[range.upperBound]
                let boundaryBefore = before.map { !$0.isLetter && !$0.isNumber } ?? true
                let boundaryAfter = after.map { !$0.isLetter && !$0.isNumber } ?? true
                if boundaryBefore && boundaryAfter { return true }
                searchRange = range.upperBound..<text.endIndex
            }
            return false
        }
    }
}
