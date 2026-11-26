import Foundation

/// `GET /api/fleet/servers/:id/metrics?range=` — one server's samples, averaged by the panel
/// into at most 400 points over the range. Admin only.
public struct FleetMetricsHistory: Decodable, Sendable, Hashable {
    public struct Point: Decodable, Sendable, Hashable {
        public var t: Date
        public var cpu: Double
        public var ram: Double
        public var disk: Double
        public var load1: Double?

        public init(t: Date, cpu: Double, ram: Double, disk: Double, load1: Double? = nil) {
            self.t = t
            self.cpu = cpu
            self.ram = ram
            self.disk = disk
            self.load1 = load1
        }
    }

    public var points: [Point]

    public init(points: [Point]) {
        self.points = points
    }
}

/// The ranges the panel accepts for metrics history.
public enum MetricsRange: String, CaseIterable, Sendable, Identifiable {
    case hour = "1h"
    case sixHours = "6h"
    case day = "24h"
    case week = "7d"
    case month = "30d"

    public var id: String { rawValue }

    public var duration: TimeInterval {
        switch self {
        case .hour:     return 3_600
        case .sixHours: return 6 * 3_600
        case .day:      return 86_400
        case .week:     return 7 * 86_400
        case .month:    return 30 * 86_400
        }
    }

    /// How many points a chart of this range shows.
    public var buckets: Int {
        switch self {
        case .hour:     return 60
        case .sixHours: return 72
        case .day:      return 96
        case .week:     return 84
        case .month:    return 90
        }
    }
}
