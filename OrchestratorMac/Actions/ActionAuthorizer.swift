import LocalAuthentication

/// Touch ID, falling back to the account password, before rollback, maintenance mode and
/// destructive commands.
@MainActor
enum ActionAuthorizer {
    /// - Returns: true when the owner authenticated. Cancelling returns false silently;
    ///   other failures say why.
    static func authorize(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            AlertPresenter.showError("Authentication is not available",
                                     error?.localizedDescription ?? "Set a login password or Touch ID first.")
            return false
        }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch let laError as LAError where [.userCancel, .appCancel, .systemCancel].contains(laError.code) {
            return false
        } catch {
            AlertPresenter.showError("Authentication failed", error.localizedDescription)
            return false
        }
    }
}
