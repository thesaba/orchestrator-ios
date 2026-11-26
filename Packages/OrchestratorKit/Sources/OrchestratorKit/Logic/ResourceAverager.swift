import Foundation

/// One point of a fleet-wide resource chart.
public struct ResourcePoint: Sendable, Hashable, Identifiable {
    public var date: Date
    public var cpu: Double
    public var ram: Double
    public var disk: Double

    public var id: Date { date }

    public init(date: Date, cpu: Double, ram: Double, disk: Double) {
        self.date = date
        self.cpu = cpu
        self.ram = ram
        self.disk = disk
    }
}

/// Averages several servers' metric histories into one series. Pure, so it is unit-tested.
///
/// The range is cut into equal time slots. Each server contributes the mean of its own
/// samples in a slot, and the slot's value is the mean over the servers that reported, so a
/// server that samples more often does not outweigh the others. Slots nobody reported in are
/// left out rather than drawn as zero.
public enum ResourceAverager {
    public static func average(_ histories: [[FleetMetricsHistory.Point]],
                               from start: Date, to end: Date, buckets: Int) -> [ResourcePoint] {
        let span = end.timeIntervalSince(start)
        guard buckets > 0, span > 0 else { return [] }
        let width = span / Double(buckets)

        // Per slot: sums of the per-server means and how many servers reported.
        var sums = [(cpu: Double, ram: Double, disk: Double, servers: Int)](repeating: (0, 0, 0, 0), count: buckets)

        for history in histories {
            var server = [(cpu: Double, ram: Double, disk: Double, samples: Int)](repeating: (0, 0, 0, 0), count: buckets)
            for point in history {
                let offset = point.t.timeIntervalSince(start)
                guard offset >= 0, offset <= span else { continue }
                let index = min(buckets - 1, Int(offset / width))
                server[index].cpu += point.cpu
                server[index].ram += point.ram
                server[index].disk += point.disk
                server[index].samples += 1
            }
            for index in 0..<buckets where server[index].samples > 0 {
                let n = Double(server[index].samples)
                sums[index].cpu += server[index].cpu / n
                sums[index].ram += server[index].ram / n
                sums[index].disk += server[index].disk / n
                sums[index].servers += 1
            }
        }

        return sums.enumerated().compactMap { index, slot in
            guard slot.servers > 0 else { return nil }
            let n = Double(slot.servers)
            return ResourcePoint(date: start.addingTimeInterval(width * (Double(index) + 0.5)),
                                 cpu: slot.cpu / n, ram: slot.ram / n, disk: slot.disk / n)
        }
    }

    /// The highest value of one metric and when it happened.
    public static func peak(_ points: [ResourcePoint], _ metric: KeyPath<ResourcePoint, Double>) -> (value: Double, date: Date)? {
        points.max { $0[keyPath: metric] < $1[keyPath: metric] }.map { ($0[keyPath: metric], $0.date) }
    }

    /// Last value minus first value, in percentage points.
    public static func change(_ points: [ResourcePoint], _ metric: KeyPath<ResourcePoint, Double>) -> Double? {
        guard let first = points.first, let last = points.last, points.count > 1 else { return nil }
        return last[keyPath: metric] - first[keyPath: metric]
    }
}
