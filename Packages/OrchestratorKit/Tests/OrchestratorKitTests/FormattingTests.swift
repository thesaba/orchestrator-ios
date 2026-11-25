import Foundation
import Testing
@testable import OrchestratorKit

@Suite("Time and duration formatting")
struct FormattingTests {
    @Test(arguments: [
        (3, "3 s"), (59, "59 s"), (68, "1 m 08 s"), (151, "2 m 31 s"), (3_840, "1 h 04 m")
    ])
    func elapsed(seconds: Int, expected: String) {
        #expect(Durations.elapsed(seconds) == expected)
    }

    @Test func elapsedWithoutValue() {
        #expect(Durations.elapsed(nil) == "—")
        #expect(Durations.elapsed(-1) == "—")
    }

    @Test func clock() {
        #expect(Durations.clock(42) == "0:42")
        #expect(Durations.clock(125) == "2:05")
        #expect(Durations.clock(3_725) == "1:02:05")
    }

    @Test func relative() {
        let now = Fixtures.now
        #expect(RelativeTime.ago(now.addingTimeInterval(-2), now: now) == "just now")
        #expect(RelativeTime.ago(now.addingTimeInterval(-5), now: now) == "5 s ago")
        #expect(RelativeTime.ago(now.addingTimeInterval(-12 * 60), now: now) == "12 min ago")
        #expect(RelativeTime.ago(now.addingTimeInterval(-2 * 3_600), now: now) == "2 h ago")
        #expect(RelativeTime.ago(now.addingTimeInterval(-5 * 86_400), now: now) == "5 days ago")
    }
}
