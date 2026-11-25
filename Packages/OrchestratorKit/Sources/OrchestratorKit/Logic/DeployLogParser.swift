import Foundation

/// Reads the panel's deploy log (written by `scripts/deploy.sh`) into steps and facts.
///
/// Format, verified against the script:
/// - `[HH:MM:SS] text` for every `log` line;
/// - `[HH:MM:SS] [N/M] Title...` opens a step, `[Nb/M]` a sub-step of step N;
/// - `__COMMIT_MSG__:`, `__COMMIT_AUTHOR__:`, `__COMMIT__:` markers without a timestamp;
/// - `[health] …` lines from the post-deploy health check;
/// - `=== Deploy complete! ===` on success.
///
/// The release goes live at step 7 (symlink swap); a deploy that stops before it leaves
/// the previous release serving.
public enum DeployLogParser {
    /// The step that swaps the `current` symlink to the new release.
    public static let activationStep = 7

    public static func parse(_ log: String, status: String?) -> DeployLogSummary {
        var accumulator = DeployLogAccumulator()
        for line in log.split(separator: "\n", omittingEmptySubsequences: true) {
            accumulator.consume(line)
        }
        return accumulator.summary(status: status)
    }

    /// "Running migrations" for `[6/8] Running migrations...`, "Deploying branch 'main' …"
    /// for `=== … ===`; nil for other lines.
    public static func stepHeaderTitle(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let step = stepHeader(in: Substring(trimmed), startedAt: nil) { return step.title }
        guard trimmed.hasPrefix("==") && trimmed.hasSuffix("==") else { return nil }
        return trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "= "))
    }

    // MARK: - Lines

    static func marker(_ prefix: String, in line: String) -> String? {
        guard line.hasPrefix(prefix) else { return nil }
        let value = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    /// `[HH:MM:SS] ` → seconds since midnight and the remainder.
    static func timestamp(in text: Substring) -> (Int, Substring)? {
        guard text.count >= 10, text.first == "[" else { return nil }
        let inner = text.dropFirst().prefix(8)
        let parts = inner.split(separator: ":")
        guard parts.count == 3,
              let h = Int(parts[0]), let m = Int(parts[1]), let s = Int(parts[2]),
              text.dropFirst(9).first == "]" else { return nil }
        let rest = text.dropFirst(10).drop(while: { $0 == " " })
        return (h * 3_600 + m * 60 + s, rest)
    }

    /// `[3b/8] Title...` → a step.
    static func stepHeader(in text: Substring, startedAt: Int?) -> DeployStep? {
        guard text.first == "[", let close = text.firstIndex(of: "]") else { return nil }
        let inside = text[text.index(after: text.startIndex)..<close]
        let pair = inside.split(separator: "/")
        guard pair.count == 2, let total = Int(pair[1]) else { return nil }
        let left = pair[0]
        let digits = left.prefix(while: \.isNumber)
        guard let number = Int(digits), number > 0, total > 0 else { return nil }
        let suffix = left.dropFirst(digits.count)
        guard suffix.allSatisfy(\.isLetter) else { return nil }

        var title = text[text.index(after: close)...].trimmingCharacters(in: .whitespaces)
        while title.hasSuffix(".") || title.hasSuffix("…") { title.removeLast() }
        let lower = title.lowercased()
        let skipped = lower.hasPrefix("skipping") || lower.contains("— skipping") || lower.contains("skipping.")

        return DeployStep(id: String(left), number: number, total: total, title: title,
                          isSubstep: !suffix.isEmpty, isSkipped: skipped, startedAt: startedAt)
    }

    // MARK: - Derived facts

    static func assignDurations(_ summary: inout DeployLogSummary, endedAt: Int?) {
        for index in summary.steps.indices {
            guard let start = summary.steps[index].startedAt else { continue }
            let end = summary.steps[(index + 1)...].first(where: { $0.startedAt != nil })?.startedAt ?? endedAt
            if let end { summary.steps[index].durationSeconds = max(0, end - start) }
        }
    }

    static func assignStates(_ summary: inout DeployLogSummary, status: String?) {
        let outcome = (status ?? "").lowercased()
        let lastIndex = summary.steps.indices.last
        for index in summary.steps.indices {
            if summary.steps[index].isSkipped {
                summary.steps[index].state = .skipped
            } else if index == lastIndex {
                switch outcome {
                case "running", "": summary.steps[index].state = .running
                case "success":     summary.steps[index].state = .done
                default:            summary.steps[index].state = .failed
                }
            } else {
                summary.steps[index].state = .done
            }
        }
    }
}

/// Parses a deploy log line by line, so a live log costs O(lines) in total instead of
/// re-reading the whole text for every new line.
public struct DeployLogAccumulator: Sendable {
    private var summary = DeployLogSummary()
    private var firstTime: Int?
    private var lastTime: Int?
    private var dayOffset = 0
    private var previousRaw: Int?

    public init() {}

    public mutating func consume(_ rawLine: some StringProtocol) {
        let line = ANSI.strip(String(rawLine)).trimmingCharacters(in: .whitespaces)
        if line.isEmpty { return }

        if let value = DeployLogParser.marker("__COMMIT_MSG__:", in: line) { summary.commitMessage = value; return }
        if let value = DeployLogParser.marker("__COMMIT_AUTHOR__:", in: line) { summary.commitAuthor = value; return }
        if let value = DeployLogParser.marker("__COMMIT__:", in: line) { summary.commit = value; return }
        if line.hasPrefix("__") { return }

        var text = Substring(line)
        var seconds: Int?
        if let stamp = DeployLogParser.timestamp(in: text) {
            let time = stamp.0
            // Deploys can run across midnight; keep the clock monotonic.
            if let previousRaw, time < previousRaw { dayOffset += 86_400 }
            previousRaw = time
            seconds = time + dayOffset
            text = stamp.1
            if firstTime == nil { firstTime = seconds }
            lastTime = seconds
        }

        if text.hasPrefix("[health]") {
            summary.healthCheckRan = true
            if text.contains("Auto-rollback") || text.contains("rolled back") { summary.rolledBack = true }
            return
        }
        if text.hasPrefix("=== Deploy complete") {
            summary.completed = true
            return
        }
        if let step = DeployLogParser.stepHeader(in: text, startedAt: seconds) {
            summary.totalSteps = max(summary.totalSteps ?? 0, step.total)
            if let index = summary.steps.lastIndex(where: { $0.id == step.id }) {
                // A repeated `[3b/8]` line continues the same step.
                if step.isSkipped == false { summary.steps[index].isSkipped = false }
            } else {
                summary.steps.append(step)
            }
        }
    }

    /// The summary so far, with step durations and states for the given outcome.
    public func summary(status: String?) -> DeployLogSummary {
        var result = summary
        if let firstTime, let lastTime {
            result.durationSeconds = lastTime - firstTime
        }
        DeployLogParser.assignDurations(&result, endedAt: lastTime)
        DeployLogParser.assignStates(&result, status: status)
        return result
    }
}

/// What a deploy log says, in a form the UI can show.
public struct DeployLogSummary: Sendable, Hashable {
    public var steps: [DeployStep] = []
    /// `M` of the `[N/M]` headers.
    public var totalSteps: Int?
    public var commit: String?
    public var commitMessage: String?
    public var commitAuthor: String?
    /// From the first to the last timestamp in the log.
    public var durationSeconds: Int?
    public var completed = false
    public var healthCheckRan = false
    public var rolledBack = false

    public init() {}

    /// The newest step header seen.
    public var currentStep: DeployStep? { steps.last }

    /// The step that failed, for a deploy that failed.
    public var failedStep: DeployStep? { steps.last(where: { $0.state == .failed }) }

    /// True when the log reached the symlink swap, so the new release went live.
    public var reachedActivation: Bool {
        steps.contains { $0.number >= DeployLogParser.activationStep }
    }

    /// Progress of a running deploy, 0…1, from the current step number.
    public var progress: Double? {
        guard let current = currentStep, let total = totalSteps, total > 0 else { return nil }
        return min(1, max(0, (Double(current.number) - 0.5) / Double(total)))
    }
}

public struct DeployStep: Sendable, Hashable, Identifiable {
    public enum State: Sendable, Hashable {
        case done, running, failed, skipped
    }

    /// `"3"` or `"3b"`.
    public var id: String
    public var number: Int
    public var total: Int
    public var title: String
    public var isSubstep: Bool
    public var isSkipped: Bool
    /// Seconds since midnight of the deploy's first day, monotonic across midnight.
    public var startedAt: Int?
    public var durationSeconds: Int?
    public var state: State = .done

    public init(id: String, number: Int, total: Int, title: String, isSubstep: Bool = false,
                isSkipped: Bool = false, startedAt: Int? = nil, durationSeconds: Int? = nil, state: State = .done) {
        self.id = id
        self.number = number
        self.total = total
        self.title = title
        self.isSubstep = isSubstep
        self.isSkipped = isSkipped
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.state = state
    }
}
