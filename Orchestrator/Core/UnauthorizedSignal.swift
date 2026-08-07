import Foundation

/// Bridges 401 responses from the nonisolated network layer to the main-actor `Session`.
///
/// A `NotificationCenter` observer would work too, but its token has to be released in
/// `deinit` — which is nonisolated — and `Notification` is not `Sendable`. A single
/// explicit handler avoids both problems.
final class UnauthorizedSignal: @unchecked Sendable {
    static let shared = UnauthorizedSignal()

    private let lock = NSLock()
    private var handler: (@MainActor @Sendable () -> Void)?

    func setHandler(_ handler: (@MainActor @Sendable () -> Void)?) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    func fire() {
        lock.lock()
        let handler = self.handler
        lock.unlock()
        guard let handler else { return }
        Task { @MainActor in handler() }
    }
}
