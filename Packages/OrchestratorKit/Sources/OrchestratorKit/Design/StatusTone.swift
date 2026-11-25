import SwiftUI

/// The single source of truth for status colour across the whole app.
///
/// Rule from the spec: a suspended or past-due site is **never** green, whatever
/// its `status` column says. `StatusTone.forSite(_:)` enforces that.
public enum StatusTone: Sendable, Hashable {
    case good
    case warning
    case critical
    case info
    case neutral

    public var color: Color {
        switch self {
        case .good:     return .green
        case .warning:  return .orange
        case .critical: return .red
        case .info:     return .blue
        case .neutral:  return .secondary
        }
    }

    public var symbol: String {
        switch self {
        case .good:     return "checkmark.circle.fill"
        case .warning:  return "exclamationmark.triangle.fill"
        case .critical: return "xmark.octagon.fill"
        case .info:     return "arrow.triangle.2.circlepath"
        case .neutral:  return "circle.dashed"
        }
    }

    /// Maps the raw status strings the API uses onto a tone.
    public init(status raw: String?) {
        let key = (raw ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        switch key {
        case "active", "up", "online", "healthy", "ok", "success", "succeeded",
             "passed", "paid", "enabled", "running_ok", "current", "none":
            self = .good
        case "suspended", "down", "offline", "failed", "error", "critical",
             "expired", "overdue", "void", "stopped", "fatal", "unhealthy",
             "cancelled", "canceled", "blocked", "past_due", "backoff":
            self = .critical
        case "degraded", "warning", "warn", "pending", "queued", "unpaid", "open",
             "draft", "expiring", "maintenance", "dry_run", "partial", "skipped",
             "banner", "grace", "paused", "unknown_slow":
            self = .warning
        case "running", "in_progress", "deploying", "provisioning", "building",
             "starting", "restarting", "issuing", "syncing":
            self = .info
        default:
            self = .neutral
        }
    }
}

extension StatusTone {
    /// Billing enforcement overrides the site's own status — a suspended site must read red.
    public static func forSite(status: String?, billingSuspended: Bool, billingPastDue: Bool, disabled: Bool) -> StatusTone {
        if billingSuspended || disabled { return .critical }
        if billingPastDue { return .warning }
        return StatusTone(status: status)
    }
}
