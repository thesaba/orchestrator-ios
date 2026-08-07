import Foundation

/// Interactive shell over `wss://…/api/terminal/:siteId?token=…`.
///
/// The server speaks JSON frames:
///   in  → `{ "type": "input",  "data": "ls -la\r" }`
///         `{ "type": "resize", "cols": 80, "rows": 24 }`
///   out ← `{ "type": "output", "data": "…" }`
///         `{ "type": "exit",   "exitCode": 0 }`
///         `{ "error": "…" }`
///
/// This is a line-oriented console, not a full terminal emulator: escape sequences are
/// stripped rather than interpreted, so `vim` and `htop` will not render. Ordinary
/// commands, tails and greps work fine.
@MainActor
@Observable
final class TerminalClient {
    enum State: Equatable {
        case idle
        case connecting
        case connected
        case closed(String?)
    }

    private(set) var state: State = .idle
    let buffer = LogBuffer()
    private(set) var exitCode: Int?

    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private let session: URLSession
    private let tokenStore: TokenStore

    init(session: URLSession = .shared, tokenStore: TokenStore = .shared) {
        self.session = session
        self.tokenStore = tokenStore
    }

    var isConnected: Bool { state == .connected }

    func connect(siteID: Int) {
        disconnect()

        guard let token = tokenStore.token, !token.isEmpty else {
            state = .closed("No token stored — sign in again.")
            return
        }

        // The WebSocket cannot carry an Authorization header through the browser API the
        // server was written for, so the token travels in the query string, as the panel does.
        var components = URLComponents(url: APIConfig.baseURL, resolvingAgainstBaseURL: false)
        components?.scheme = (APIConfig.baseURL.scheme == "http") ? "ws" : "wss"
        components?.path = "\(APIConfig.apiPath)/terminal/\(siteID)"
        components?.queryItems = [URLQueryItem(name: "token", value: token)]

        guard let url = components?.url else {
            state = .closed("Could not build the terminal URL.")
            return
        }

        buffer.clear()
        exitCode = nil
        state = .connecting

        let socket = session.webSocketTask(with: url)
        task = socket
        socket.resume()
        state = .connected
        buffer.append("— connected —")

        receiveTask = Task { [weak self] in
            await self?.receiveLoop(socket)
        }
    }

    func send(_ command: String) {
        guard let task, state == .connected else { return }
        buffer.append("$ \(command)")
        let payload = ["type": "input", "data": command + "\n"]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return }
        task.send(.string(text)) { [weak self] error in
            // Bind strongly here: re-capturing the weak optional inside the nested Task is
            // an error under the Swift 6 language mode.
            guard let error, let self else { return }
            let message = error.localizedDescription
            Task { @MainActor in
                self.state = .closed(message)
            }
        }
    }

    /// Ctrl-C, for a command that will not stop on its own.
    func sendInterrupt() {
        guard let task, state == .connected else { return }
        buffer.append("^C")
        let payload = ["type": "input", "data": "\u{0003}"]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return }
        task.send(.string(text)) { _ in }
    }

    func disconnect() {
        receiveTask?.cancel()
        receiveTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        if case .connected = state { state = .closed(nil) }
    }

    private func receiveLoop(_ socket: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let message = try await socket.receive()
                switch message {
                case .string(let text):
                    handle(text)
                case .data(let data):
                    handle(String(data: data, encoding: .utf8) ?? "")
                @unknown default:
                    break
                }
            } catch {
                if !Task.isCancelled {
                    state = .closed(URLError.Code(rawValue: (error as NSError).code) == .cancelled
                                    ? nil
                                    : error.localizedDescription)
                }
                return
            }
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let value = try? APIClient.decoder.decode(JSONValue.self, from: data) else {
            buffer.append(text)
            return
        }

        if let error = value["error"]?.stringValue, !error.isEmpty {
            buffer.append("!! \(error)")
            state = .closed(error)
            disconnect()
            return
        }

        switch value["type"]?.stringValue {
        case "output":
            if let output = value["data"]?.stringValue, !output.isEmpty {
                buffer.append(output)
            }
        case "exit":
            let code = value["exitCode"]?.intValue
            exitCode = code
            buffer.append("— session ended (exit code \(code.map(String.init) ?? "?")) —")
            state = .closed(nil)
        default:
            if let output = value["data"]?.stringValue { buffer.append(output) }
        }
    }
}
