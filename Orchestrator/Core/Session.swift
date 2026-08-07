import Foundation
import SwiftUI

/// Owns authentication state for the whole app.
///
/// A Personal Access Token is the primary credential; JWT email/password login
/// (with optional TOTP) is the fallback. Either way the bearer token lives in the
/// Keychain and nowhere else.
@MainActor
@Observable
final class Session {
    enum Phase: Equatable {
        case launching
        case signedOut
        case signedIn
    }

    enum PasswordLoginResult: Equatable {
        case signedIn
        case requiresTOTP
    }

    private(set) var phase: Phase = .launching
    private(set) var user: User?
    private(set) var tokenKind: TokenKind?
    private(set) var isWorking = false

    /// Surfaced on the sign-in screen. Never contains the token itself.
    var signInError: String?

    /// True when a token is on file but could not be validated (e.g. offline at launch).
    private(set) var hasStoredToken = false

    private let client: APIClient
    private let tokenStore: TokenStore
    private var isObservingUnauthorized = false

    init(client: APIClient = .shared, tokenStore: TokenStore = .shared) {
        self.client = client
        self.tokenStore = tokenStore
        self.hasStoredToken = tokenStore.hasToken
    }

    // MARK: - Launch

    func bootstrap() async {
        observeUnauthorized()
        hasStoredToken = tokenStore.hasStoredToken
        guard hasStoredToken else {
            phase = .signedOut
            return
        }

        // App lock is on and the token is still sealed behind biometrics: there is no
        // bearer to validate with yet. Go straight to signed-in so the lock screen can
        // cover the app, and fetch the account once it is unlocked.
        if tokenStore.isSealed {
            user = nil
            tokenKind = tokenStore.kind
            phase = .signedIn
            return
        }
        do {
            user = try await client.get("/auth/me", as: User.self)
            tokenKind = tokenStore.kind
            signInError = nil
            phase = .signedIn
        } catch let error as APIError where error.isUnauthorized {
            tokenStore.clear()
            hasStoredToken = false
            signInError = "The saved token is no longer valid. Paste a new one."
            phase = .signedOut
        } catch {
            // Network problem, not a credential problem — keep the token so a retry is one tap.
            signInError = APIError.wrap(error).errorDescription
            phase = .signedOut
        }
    }

    // MARK: - Personal access token

    func signIn(personalAccessToken raw: String) async {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            signInError = "Paste your personal access token first."
            return
        }
        await authenticate(with: token, kind: .personalAccessToken)
    }

    /// Re-validates whatever token is already in the Keychain.
    func retryStoredToken() async {
        guard let token = tokenStore.token else {
            phase = .signedOut
            return
        }
        await authenticate(with: token, kind: tokenStore.kind ?? TokenKind.inferred(from: token))
    }

    // MARK: - Email + password (+ TOTP)

    func signIn(email: String, password: String, totpCode: String?) async throws -> PasswordLoginResult {
        isWorking = true
        signInError = nil
        defer { isWorking = false }

        let trimmedCode = totpCode?.trimmingCharacters(in: .whitespaces)
        let body = LoginRequest(
            email: email.trimmingCharacters(in: .whitespaces),
            password: password,
            totpCode: (trimmedCode?.isEmpty ?? true) ? nil : trimmedCode
        )

        let response: LoginResponse = try await client.post("/auth/login", body: body)

        if let token = response.token, !token.isEmpty {
            await authenticate(with: token, kind: .jwt)
            return .signedIn
        }
        if response.requiresTOTP {
            return .requiresTOTP
        }
        throw APIError.http(status: 200, message: response.message ?? "The server did not return a token.")
    }

    // MARK: - Sign out

    func signOut() {
        tokenStore.clear()
        hasStoredToken = false
        user = nil
        tokenKind = nil
        signInError = nil
        phase = .signedOut
    }

    // MARK: - Internals

    private func authenticate(with token: String, kind: TokenKind) async {
        isWorking = true
        signInError = nil
        defer { isWorking = false }

        do {
            try tokenStore.store(token, kind: kind)
            let me: User = try await client.get("/auth/me")
            user = me
            tokenKind = kind
            hasStoredToken = true
            phase = .signedIn
        } catch {
            let apiError = APIError.wrap(error)
            tokenStore.clear()
            hasStoredToken = false
            user = nil
            phase = .signedOut
            signInError = apiError.isUnauthorized
                ? "That token was rejected. Check that you copied it in full."
                : apiError.errorDescription
        }
    }

    /// Registered here rather than in `init` — capturing `self` in an escaping closure
    /// during initialisation is an error under the Swift 6 language mode.
    private func observeUnauthorized() {
        guard !isObservingUnauthorized else { return }
        isObservingUnauthorized = true
        UnauthorizedSignal.shared.setHandler { [weak self] in
            self?.handleUnauthorized()
        }
    }

    /// Fills in `/auth/me` after the app lock has been opened.
    func refreshUserIfNeeded() async {
        guard phase == .signedIn, user == nil, tokenStore.hasToken else { return }
        do {
            user = try await client.get("/auth/me", as: User.self)
            tokenKind = tokenStore.kind
        } catch let error as APIError where error.isUnauthorized {
            signOut()
            signInError = "The saved token is no longer valid. Paste a new one."
        } catch {
            signInError = APIError.wrap(error).errorDescription
        }
    }

    private func handleUnauthorized() {
        guard phase == .signedIn else { return }
        // While the app is locked the token is deliberately absent, so requests come back
        // 401. That is the lock working, not an expired credential — do not sign out.
        guard !tokenStore.isSealed else { return }
        tokenStore.clear()
        hasStoredToken = false
        user = nil
        tokenKind = nil
        phase = .signedOut
        signInError = "Your session expired. Sign in again."
    }
}
