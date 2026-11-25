import Foundation

/// Display names for `FleetAlertEvent.kind`, matching the panel's alert kinds.
public enum FleetAlertKind {
    /// "Disk at 91%", "CPU at 97%", "Server offline" — the headline of an alert.
    public static func headline(kind: String, value: Double?, message: String?) -> String {
        let percent = value.map { "\(Int($0.rounded()))%" }
        switch kind {
        case "cpu":            return percent.map { "CPU at \($0)" } ?? "High CPU"
        case "ram":            return percent.map { "RAM at \($0)" } ?? "High memory"
        case "disk":           return percent.map { "Disk at \($0)" } ?? "Disk almost full"
        case "swap":           return percent.map { "Swap at \($0)" } ?? "High swap use"
        case "inode":          return percent.map { "Inodes at \($0)" } ?? "Inodes almost used up"
        case "load":           return value.map { "Load \(String(format: "%.1f", $0))" } ?? "High load"
        case "offline":        return "Server offline"
        case "disk_forecast":  return "Disk fills up soon"
        case "service_failed": return "Service failed"
        default:               return message ?? kind.capitalized
        }
    }

    /// Short form for a server row and the alerts breakdown: "Disk 91%", "Offline".
    public static func shortLabel(kind: String, value: Double?) -> String {
        let percent = value.map { " \(Int($0.rounded()))%" } ?? ""
        switch kind {
        case "cpu":            return "CPU" + percent
        case "ram":            return "RAM" + percent
        case "disk":           return "Disk" + percent
        case "swap":           return "Swap" + percent
        case "inode":          return "Inodes" + percent
        case "load":           return value.map { "Load \(String(format: "%.1f", $0))" } ?? "Load"
        case "offline":        return "Offline"
        case "disk_forecast":  return "Disk forecast"
        case "service_failed": return "Service failed"
        default:               return kind.capitalized
        }
    }

    /// Category used in the "1 disk · 1 SSL" breakdown.
    public static func category(kind: String) -> String {
        switch kind {
        case "disk", "disk_forecast", "inode": return "disk"
        case "cpu", "load":                    return "CPU"
        case "ram", "swap":                    return "RAM"
        case "offline":                        return "offline"
        case "service_failed":                 return "service"
        default:                               return kind
        }
    }

    /// Kinds that mean the server is down rather than degraded.
    public static func isCritical(kind: String) -> Bool { kind == "offline" }
}
