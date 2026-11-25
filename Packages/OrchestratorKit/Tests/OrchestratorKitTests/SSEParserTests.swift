import Foundation
import Testing
@testable import OrchestratorKit

@Suite("Server-sent events parsing")
struct SSEParserTests {
    /// Exactly what the panel's deploy stream writes: `data: <json>\n\n`, `: ka` heartbeats.
    @Test func deliversEachEventAtItsBlankLine() {
        var parser = SSEParser()
        let first = parser.feed(Array(#"data: {"line":"[12:00:01] [1/8] Cloning repository..."}"#.utf8) + [10])
        #expect(first.isEmpty)                       // not yet: the blank line ends the event
        let completed = parser.feed([10])
        #expect(completed.count == 1)
        #expect(completed.first?.message?.line == "[12:00:01] [1/8] Cloning repository...")

        let rest = parser.feed(Array(": ka\n\ndata: {\"done\":true,\"status\":\"success\"}\n\n".utf8))
        #expect(rest.count == 1)
        #expect(rest.first?.message?.isDone == true)
        #expect(rest.first?.message?.outcome == .success)
    }

    @Test func idleStreamAnswersDoneUnknown() {
        var parser = SSEParser()
        let events = parser.feed(Array("data: {\"done\":true,\"status\":\"unknown\"}\n\n".utf8))
        #expect(events.first?.message?.status == "unknown")
    }

    @Test func handlesCRLFMultilineDataAndFields() {
        var parser = SSEParser()
        let events = parser.feed(Array("event: log\r\nid: 7\r\ndata: one\r\ndata: two\r\n\r\n".utf8))
        #expect(events == [SSEEvent(event: "log", id: "7", data: "one\ntwo")])
    }

    @Test func eventsSplitAcrossChunks() {
        var parser = SSEParser()
        let text = Array("data: {\"line\":\"a\"}\n\ndata: {\"line\":\"b\"}\n\n".utf8)
        var events: [SSEEvent] = []
        for chunk in stride(from: 0, to: text.count, by: 5).map({ Array(text[$0..<min($0 + 5, text.count)]) }) {
            events += parser.feed(chunk)
        }
        #expect(events.compactMap { $0.message?.line } == ["a", "b"])
    }

    @Test func unicodeAndFinishWithoutBlankLine() {
        var parser = SSEParser()
        #expect(parser.feed(Array("data: {\"line\":\"✓ built — ok\"}".utf8)).isEmpty)
        #expect(parser.finish()?.message?.line == "✓ built — ok")
        #expect(parser.finish() == nil)
    }
}
