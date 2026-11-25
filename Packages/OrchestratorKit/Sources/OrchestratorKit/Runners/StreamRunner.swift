import Foundation

/// Drives one SSE endpoint into a `LogBuffer` and tracks its terminal state.
///
/// Used by deploy, provision, SSL issuance, artisan, live logs, server prepare and system
/// ops — every `/stream` route speaks the same `{ line }` / `{ done, status }` protocol.
@MainActor
@Observable
public final class StreamRunner {
    public let buffer = LogBuffer()

    public private(set) var isStreaming = false
    public private(set) var outcome: StreamOutcome?
    public private(set) var lastStatus: String?
    public private(set) var streamError: String?
    /// Bumped on every reconnect so the UI can say so instead of looking frozen.
    public private(set) var reconnectCount = 0

    private var task: Task<Void, Never>?
    private var source: (() -> AsyncThrowingStream<SSEEvent, Error>)?

    public var isFinished: Bool { outcome != nil }

    public init() {}

    /// - Parameter reconnectOnDrop: the server replays its buffer on reattach, so a dropped
    ///   connection mid-deploy is recoverable. Retries stop once the stream reports `done`.
    public func start(reconnectOnDrop: Bool = true,
               clearBuffer: Bool = true,
               source: @escaping () -> AsyncThrowingStream<SSEEvent, Error>) {
        stop()

        if clearBuffer { buffer.clear() }
        self.source = source
        outcome = nil
        lastStatus = nil
        streamError = nil
        reconnectCount = 0
        isStreaming = true

        task = Task { [weak self] in
            var attempt = 0

            while !Task.isCancelled {
                guard let self else { return }
                do {
                    for try await event in source() {
                        try Task.checkCancellation()
                        guard let message = event.message else {
                            if !event.data.isEmpty { self.buffer.append(event.data) }
                            continue
                        }
                        if let line = message.line { self.buffer.append(line) }
                        if let status = message.status { self.lastStatus = status }
                        if let error = message.error, !error.isEmpty {
                            self.buffer.append("!! \(error)")
                            self.streamError = error
                        }
                        if message.isDone {
                            self.outcome = message.outcome ?? .success
                            self.isStreaming = false
                            return
                        }
                    }
                    // Clean end without a `done` frame: treat as finished if we saw a status.
                    if self.outcome == nil, !reconnectOnDrop {
                        self.outcome = self.lastStatus.map { StreamOutcome(rawValue: $0) ?? .success }
                        self.isStreaming = false
                        return
                    }
                } catch is CancellationError {
                    self.isStreaming = false
                    return
                } catch {
                    let apiError = APIError.wrap(error)
                    if apiError.isCancellation {
                        self.isStreaming = false
                        return
                    }
                    if !reconnectOnDrop || attempt >= 4 {
                        self.streamError = apiError.errorDescription
                        self.outcome = .failed
                        self.isStreaming = false
                        return
                    }
                }

                guard reconnectOnDrop, !Task.isCancelled else { break }
                attempt += 1
                self.reconnectCount = attempt
                self.buffer.append("— reconnecting (\(attempt)/4) —")
                try? await Task.sleep(for: .seconds(min(8, attempt * 2)))
            }

            // Outside the `guard let self` scope of the loop body.
            self?.isStreaming = false
        }
    }

    /// Reattaches to the same endpoint, keeping what is already on screen.
    public func reattach() {
        guard let source else { return }
        start(clearBuffer: false, source: source)
    }

    /// Views must call this from `.onDisappear`; a nonisolated `deinit` cannot reach the
    /// main-actor task, and the running task keeps this object alive until it is cancelled.
    public func stop() {
        task?.cancel()
        task = nil
        isStreaming = false
    }
}
