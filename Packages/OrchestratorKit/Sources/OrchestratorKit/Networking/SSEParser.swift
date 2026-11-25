import Foundation

/// Incremental server-sent-events parser, fed one byte at a time.
///
/// Replaces `URLSession.AsyncBytes.lines`, which drops empty lines — and in SSE the empty
/// line is what ends an event, so with it no event was delivered until the connection closed.
public struct SSEParser: Sendable {
    private var line: [UInt8] = []
    private var name: String?
    private var identifier: String?
    private var dataLines: [String] = []

    public init() {}

    /// Returns an event when `byte` completes one (the blank line after its fields).
    public mutating func feed(_ byte: UInt8) -> SSEEvent? {
        guard byte == UInt8(ascii: "\n") else {
            line.append(byte)
            return nil
        }
        if line.last == UInt8(ascii: "\r") { line.removeLast() }
        let text = String(decoding: line, as: UTF8.self)
        line.removeAll(keepingCapacity: true)
        return process(text)
    }

    /// Convenience for tests and chunked input.
    public mutating func feed(_ bytes: some Sequence<UInt8>) -> [SSEEvent] {
        bytes.compactMap { feed($0) }
    }

    /// At end of stream: an event whose terminating blank line never arrived.
    public mutating func finish() -> SSEEvent? {
        if !line.isEmpty {
            let text = String(decoding: line, as: UTF8.self)
            line.removeAll()
            if let event = process(text) { return event }
        }
        return dispatch()
    }

    private mutating func process(_ text: String) -> SSEEvent? {
        if text.isEmpty { return dispatch() }
        if text.hasPrefix(":") { return nil }   // comment / heartbeat

        let field: Substring
        var value: Substring
        if let colon = text.firstIndex(of: ":") {
            field = text[text.startIndex..<colon]
            value = text[text.index(after: colon)...]
            if value.hasPrefix(" ") { value = value.dropFirst() }
        } else {
            field = Substring(text)
            value = ""
        }

        switch field {
        case "data":  dataLines.append(String(value))
        case "event": name = String(value)
        case "id":    identifier = String(value)
        default:      break
        }
        return nil
    }

    private mutating func dispatch() -> SSEEvent? {
        defer {
            name = nil
            identifier = nil
            dataLines.removeAll()
        }
        guard !dataLines.isEmpty else { return nil }
        return SSEEvent(event: name, id: identifier, data: dataLines.joined(separator: "\n"))
    }
}
