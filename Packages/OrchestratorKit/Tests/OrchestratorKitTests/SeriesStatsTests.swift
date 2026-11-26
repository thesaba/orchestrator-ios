import Foundation
import Testing
@testable import OrchestratorKit

@Suite("Chart series statistics")
struct SeriesStatsTests {
    private func series(_ values: [Double]) -> [SeriesPoint] {
        values.enumerated().map { SeriesPoint(date: Fixtures.now.addingTimeInterval(Double($0.offset) * 60), value: $0.element) }
    }

    @Test func summarises() throws {
        let stats = try #require(SeriesStats(series([20, 80, 50, 10, 40])))
        #expect(stats.latest == 40)
        #expect(stats.average == 40)
        #expect(stats.maximum.value == 80)
        #expect(stats.maximum.date == Fixtures.now.addingTimeInterval(60))
        #expect(stats.minimum.value == 10)
        #expect(stats.count == 5)
        #expect(SeriesStats([]) == nil)
    }

    @Test func nearestPointForHover() {
        let points = series([1, 2, 3, 4])
        #expect(SeriesStats.nearest(to: Fixtures.now.addingTimeInterval(-500), in: points)?.value == 1)
        #expect(SeriesStats.nearest(to: Fixtures.now.addingTimeInterval(80), in: points)?.value == 2)
        #expect(SeriesStats.nearest(to: Fixtures.now.addingTimeInterval(100), in: points)?.value == 3)
        #expect(SeriesStats.nearest(to: Fixtures.now.addingTimeInterval(9_000), in: points)?.value == 4)
        #expect(SeriesStats.nearest(to: Fixtures.now, in: []) == nil)
    }
}
