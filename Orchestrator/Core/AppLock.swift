import Foundation
import LocalAuthentication
import SwiftUI
import OrchestratorKit

/// Optional Face ID / Touch ID / passcode gate in front of the whole app.
///
/// The gate is not cosmetic: when it is on, the API token is stored with a
/// `SecAccessControl`, so iOS refuses to return it without a successful check. Unlocking
/// *is* the keychain read — there is no separate "check biometrics, then read anyway" step
/// that could be bypassed by tampering with the app.
@MainActor
@Observable
final class AppLock {
    enum State: Equatable {
        case unlocked
        case locked
        case authenticating
    }

    /// How long the app may sit in the background before it re-locks.
    static let graceInterval: TimeInterval = 60

    private(set) var state: State = .unlocked
    private(set) var isEnabled: Bool
    var lastError: String?

    /// False until the first successful unlock of this launch.
    ///
    /// Before that the app's view tree must not be built at all: a `.task` firing behind
    /// the lock screen would load with no bearer, cache the failure, and still be showing
    /// it after the user authenticates.
    private(set) var hasUnlockedOnce = false

    private let tokenStore: TokenStore
    private var backgroundedAt: Date?

    /// Mirrors `TokenStore.isProtected` — deriving it from the keychain state rather than
    /// a separate flag makes it impossible for the two to disagree (e.g. "lock enabled"
    /// with an unprotected token after a sign-out).
    init(tokenStore: TokenStore = .shared) {
        self.tokenStore = tokenStore
        self.isEnabled = tokenStore.isProtected
        // A protected token that is not in memory yet means we are starting cold and locked.
        let sealed = tokenStore.isSealed
        self.state = sealed ? .locked : .unlocked
        self.hasUnlockedOnce = !sealed
    }

    /// True on a cold launch that has never been unlocked — the point at which building
    /// the tab hierarchy would be premature.
    var needsFirstUnlock: Bool { state != .unlocked && !hasUnlockedOnce }

    // MARK: - Capability

    /// "Face ID", "Touch ID", "Optic ID" — or nil when no biometry is enrolled.
    var biometryName: String? {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return nil }
        switch context.biometryType {
        case .faceID:  return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default:       return nil
        }
    }

    /// Whether the device can authenticate at all — biometry *or* a passcode.
    var canAuthenticate: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    var unlockMethodDescription: String {
        biometryName ?? "your device passcode"
    }

    var symbol: String {
        switch biometryName {
        case "Face ID":  return "faceid"
        case "Touch ID": return "touchid"
        case "Optic ID": return "opticid"
        default:         return "lock.fill"
        }
    }

    // MARK: - Turning it on and off

    func enable() async throws {
        guard canAuthenticate else {
            throw AppLockError.noAuthenticationAvailable
        }
        try await Task.detached(priority: .userInitiated) { [tokenStore] in
            try tokenStore.setProtection(true)
        }.value

        isEnabled = true
        state = .unlocked
        hasUnlockedOnce = true
        lastError = nil
    }

    func disable() async throws {
        // Requires the token in memory; if the app is unlocked it always is.
        try await Task.detached(priority: .userInitiated) { [tokenStore] in
            try tokenStore.setProtection(false)
        }.value

        isEnabled = false
        state = .unlocked
        lastError = nil
    }

    // MARK: - Locking

    func lock() {
        guard isEnabled else { return }
        tokenStore.lockNow()
        state = .locked
    }

    func unlock() async {
        guard state != .authenticating else { return }
        state = .authenticating
        lastError = nil

        let reason = "Unlock Orchestrator"
        do {
            // Blocking keychain read with a `LAContext` — must not run on the main actor.
            try await Task.detached(priority: .userInitiated) { [tokenStore] in
                _ = try tokenStore.unlock(reason: reason)
            }.value
            state = .unlocked
            hasUnlockedOnce = true
        } catch let error as KeychainError {
            state = .locked
            switch error {
            case .userCancelled:
                lastError = nil
            case .itemNotFound:
                lastError = "No token is stored on this device any more. Sign in again."
            default:
                lastError = error.errorDescription
            }
        } catch {
            state = .locked
            lastError = error.localizedDescription
        }
    }

    // MARK: - Scene phase

    func handleScenePhase(_ phase: ScenePhase) {
        guard isEnabled else { return }

        switch phase {
        case .background, .inactive:
            if backgroundedAt == nil { backgroundedAt = .now }
        case .active:
            defer { backgroundedAt = nil }
            guard let backgroundedAt else { return }
            if Date.now.timeIntervalSince(backgroundedAt) >= Self.graceInterval {
                lock()
            }
        @unknown default:
            break
        }
    }

    /// Called when the session signs out, so the next sign-in is not stuck behind a lock
    /// screen guarding a token that no longer exists. `TokenStore.clear()` already drops
    /// the protection flag; this just brings the observable copy back in step.
    func reset() {
        isEnabled = tokenStore.isProtected
        state = .unlocked
        hasUnlockedOnce = true
        backgroundedAt = nil
        lastError = nil
    }
}

enum AppLockError: LocalizedError {
    case noAuthenticationAvailable

    var errorDescription: String? {
        switch self {
        case .noAuthenticationAvailable:
            return "This device has no passcode or biometrics set up, so the app cannot be locked."
        }
    }
}
