import Foundation

/// One timestamped value of a chart series.
public struct SeriesPoint: Sendable, Hashable, Identifiable {
    public var date: Date
    public var value: Double

    public var id: Date { date }

    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

/// Now, average, lowest and highest of a series, with when the extremes happened. Pure, so
/// it is unit-tested; the expanded charts show it under the chart.
public struct SeriesStats: Sendable, Hashable {
    public var latest: Double
    public var average: Double
    public var minimum: SeriesPoint
    public var maximum: SeriesPoint
    public var count: Int

    public init?(_ points: [SeriesPoint]) {
        guard let last = points.last,
              let low = points.min(by: { $0.value < $1.value }),
              let high = points.max(by: { $0.value < $1.value }) else { return nil }
        latest = last.value
        average = points.reduce(0) { $0 + $1.value } / Double(points.count)
        minimum = low
        maximum = high
        count = points.count
    }

    /// The point whose date is closest to `date`, for a hover readout.
    public static func nearest(to date: Date, in points: [SeriesPoint]) -> SeriesPoint? {
        guard !points.isEmpty else { return nil }
        // Points are sorted by date: binary search, then compare the neighbours.
        var low = 0, high = points.count - 1
        while low < high {
            let mid = (low + high) / 2
            if points[mid].date < date { low = mid + 1 } else { high = mid }
        }
        let candidate = points[low]
        if low > 0 {
            let previous = points[low - 1]
            if abs(previous.date.timeIntervalSince(date)) <= abs(candidate.date.timeIntervalSince(date)) { return previous }
        }
        return candidate
    }
}
