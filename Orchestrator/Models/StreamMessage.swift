import Foundation

/// One decoded SSE payload from any of the streaming endpoints
/// (deploy, provision, ssl, artisan, live logs, server prepare, system ops).
///
/// The documented shape is `{ line: "..." }` for output and
/// `{ done: true, status: "success" | "failed" | ... }` on completion, but the raw
/// payload is kept so screens can read extra fields without a model change.
struct StreamMessage: Decodable, Sendable {
    var line: String?
    var isDone: Bool
    var status: String?
    var error: String?
    var progress: Double?
    var step: String?
    var raw: JSONValue

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(JSONValue.self)
        raw = value
        line = value["line"]?.stringValue
            ?? value["output"]?.stringValue
            ?? value["log"]?.stringValue
            ?? value["message"]?.stringValue
        isDone = value["done"]?.boolValue ?? false
        status = value["status"]?.stringValue
        error = value["error"]?.stringValue
        progress = value["progress"]?.doubleValue
        step = value["step"]?.stringValue ?? value["stage"]?.stringValue
    }

    /// Terminal state reported by the server, if any.
    var outcome: StreamOutcome? {
        guard isDone else { return nil }
        switch (status ?? (error == nil ? "success" : "failed")).lowercased() {
        case "success", "succeeded", "ok", "done", "completed": return .success
        case "cancelled", "canceled", "aborted":                return .cancelled
        default:                                                return .failed
        }
    }
}

enum StreamOutcome: String, Sendable {
    case success, failed, cancelled

    var tone: StatusTone {
        switch self {
        case .success:   return .good
        case .failed:    return .critical
        case .cancelled: return .warning
        }
    }
}

extension SSEEvent {
    /// `nil` when the payload is not JSON (some servers emit a bare keep-alive).
    var message: StreamMessage? {
        guard let payload = data.data(using: .utf8) else { return nil }
        return try? APIClient.decoder.decode(StreamMessage.self, from: payload)
    }
}
