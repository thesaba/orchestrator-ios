import Foundation

/// One fleet server with its mark and the one-line state shown under its name.
public struct ServerStatus: Sendable, Hashable, Identifiable {
    public var server: FleetServer
    public var mark: HealthMark
    /// "Healthy", "Disk 91%", "Offline", "No data".
    public var label: String
    public var alerts: [FleetAlertEvent]

    public var id: Int { server.id }

    /// The metric a compact row shows: the one that triggered a warning, otherwise CPU.
    public var headlineMetric: (name: String, percent: Double?) {
        switch alerts.first?.kind {
        case "ram", "swap":                    return ("RAM", server.ramPercent)
        case "disk", "disk_forecast", "inode": return ("Disk", server.diskPercent)
        default:                               return ("CPU", server.cpuPercent)
        }
    }

    public init(server: FleetServer, mark: HealthMark, label: String, alerts: [FleetAlertEvent] = []) {
        self.server = server
        self.mark = mark
        self.label = label
        self.alerts = alerts
    }
}
