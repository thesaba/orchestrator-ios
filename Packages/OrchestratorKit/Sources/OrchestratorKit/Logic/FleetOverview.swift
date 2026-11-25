import Foundation

/// Everything the popover, the menu bar item and the widgets show, derived in one place.
public struct FleetOverview: Sendable, Hashable {
    public struct ServerCounts: Sendable, Hashable {
        public var total = 0
        public var healthy = 0
        public var warning = 0
        public var failure = 0
        public var unknown = 0

        public init() {}

        /// "9 healthy · 1 warning".
        public var breakdown: String {
            var parts = ["\(healthy) healthy"]
            if warning > 0 { parts.append("\(warning) warning") }
            if failure > 0 { parts.append("\(failure) offline") }
            if unknown > 0 { parts.append("\(unknown) no data") }
            return parts.joined(separator: " · ")
        }
    }

    public struct SiteCounts: Sendable, Hashable {
        public var total = 0
        public var up = 0
        public var down = 0
        public var deploying = 0

        public init() {}

        /// "11 up · 1 deploying".
        public var breakdown: String {
            var parts = ["\(up) up"]
            if deploying > 0 { parts.append("\(deploying) deploying") }
            if down > 0 { parts.append("\(down) down") }
            return parts.joined(separator: " · ")
        }
    }

    /// Worst first.
    public var servers: [ServerStatus] = []
    /// Deploying first, then worst first.
    public var sites: [SiteStatus] = []
    public var attention: [AttentionItem] = []
    public var serverCounts = ServerCounts()
    public var siteCounts = SiteCounts()

    public init() {}

    public var alertCount: Int { attention.count }
    public var isDeploying: Bool { siteCounts.deploying > 0 }

    /// "1 disk · 1 SSL", or "None" without alerts.
    public var alertBreakdown: String {
        guard !attention.isEmpty else { return "None" }
        var order: [String] = []
        var counts: [String: Int] = [:]
        for item in attention {
            if counts[item.category] == nil { order.append(item.category) }
            counts[item.category, default: 0] += 1
        }
        return order.map { "\(counts[$0] ?? 0) \($0)" }.joined(separator: " · ")
    }

    /// "All systems healthy" or "2 items need attention".
    public var summary: String {
        switch attention.count {
        case 0:  return "All systems healthy"
        case 1:  return "1 item needs attention"
        default: return "\(attention.count) items need attention"
        }
    }

    /// The mark next to the menu bar glyph; nil when everything is healthy.
    public var menuBarMark: HealthMark? {
        if isDeploying { return .deploying }
        if attention.contains(where: { $0.severity == .failure }) { return .failure }
        if !attention.isEmpty { return .warning }
        return nil
    }
}
