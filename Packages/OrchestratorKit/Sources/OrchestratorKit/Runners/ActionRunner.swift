import Foundation

/// Shared plumbing for "user tapped a button that changes the server".
///
/// Keeps the in-flight flag, the last error and a transient confirmation message in one
/// place so no screen silently swallows a failure.
@MainActor
@Observable
public final class ActionRunner {
    public private(set) var runningLabel: String?
    public var errorMessage: String?
    public var successMessage: String?

    public var isRunning: Bool { runningLabel != nil }

    public init() {}

    public func isRunning(_ label: String) -> Bool { runningLabel == label }

    /// - Parameter onSuccess: run after the call succeeds, typically a refresh.
    public func run(_ label: String,
             success: String? = nil,
             operation: @escaping () async throws -> Void,
             onSuccess: (() async -> Void)? = nil) async {
        guard runningLabel == nil else { return }
        runningLabel = label
        errorMessage = nil
        successMessage = nil
        defer { runningLabel = nil }

        do {
            try await operation()
            successMessage = success
            await onSuccess?()
        } catch {
            errorMessage = APIError.wrap(error).errorDescription
        }
    }

    public func clear() {
        errorMessage = nil
        successMessage = nil
    }
}
