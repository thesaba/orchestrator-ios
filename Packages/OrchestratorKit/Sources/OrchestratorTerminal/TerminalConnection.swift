import Foundation
import Observation
import OrchestratorKit

/// One terminal WebSocket of the panel: the site shell (`/api/terminal/:siteId`) or a
/// server shell (`/api/terminal/fleet/term/:serverId`). Both speak the same JSON:
/// `{type:"input",data}` and `{type:"resize",cols,rows}` out, `{type:"output",data}`,
/// `{type:"exit",exitCode}` or `{error}` in.
@MainActor
@Observable
public final class TerminalConnection {
    public enum State: Equatable {
        case connecting
        case connected
        case closed(String)
    }

    public private(set) var state: State = .connecting

    /// Called with each chunk of output, on the main actor.
    @ObservationIgnored public var onOutput: ((String) -> Void)?

    @ObservationIgnored private let url: URL
    @ObservationIgnored private var task: URLSessionWebSocketTask?
    @ObservationIgnored private let session = URLSession(configuration: .default)
    @ObservationIgnored private var pendingSize: (cols: Int, rows: Int)?

    public init(url: URL) {
        self.url = url
    }

    public func connect() {
        task?.cancel(with: .goingAway, reason: nil)
        state = .connecting
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        receive(on: task)
    }

    public func disconnect() {
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        if case .closed = state {} else { state = .closed("Disconnected.") }
    }

    /// Keys typed in the terminal.
    public func send(input: String) {
        send(["type": "input", "data": input])
    }

    public func resize(cols: Int, rows: Int) {
        guard cols > 0, rows > 0 else { return }
        if state == .connected {
            send(["type": "resize", "cols": cols, "rows": rows])
        } else {
            pendingSize = (cols, rows)
        }
    }

    private func send(_ object: [String: Any]) {
        guard let task, let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else { return }
        task.send(.string(text)) { _ in }
    }

    private func receive(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            Task { @MainActor [weak self] in self?.received(result, on: task) }
        }
    }

    private func received(_ result: Result<URLSessionWebSocketTask.Message, Error>, on task: URLSessionWebSocketTask) {
        guard self.task === task else { return }
        switch result {
        case .failure(let error):
            if case .closed = state {} else { state = .closed(Self.describe(error)) }
        case .success(let message):
            switch message {
            case .string(let text): handle(text)
            case .data(let data):   handle(String(decoding: data, as: UTF8.self))
            @unknown default:       break
            }
            if case .closed = state { return }
            receive(on: task)
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            markConnected()
            onOutput?(text)
            return
        }
        if let error = object["error"] as? String {
            state = .closed(error)
            task?.cancel(with: .normalClosure, reason: nil)
            return
        }
        switch object["type"] as? String {
        case "output":
            markConnected()
            if let output = object["data"] as? String { onOutput?(output) }
        case "exit":
            let code = (object["exitCode"] as? Int).map { " (exit code \($0))" } ?? ""
            state = .closed("The shell ended\(code).")
        default:
            markConnected()
        }
    }

    private func markConnected() {
        guard state != .connected else { return }
        state = .connected
        if let size = pendingSize {
            pendingSize = nil
            resize(cols: size.cols, rows: size.rows)
        }
    }

    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorBadServerResponse {
            return "The panel refused the terminal. Sign in again with your password."
        }
        return error.localizedDescription
    }
}
