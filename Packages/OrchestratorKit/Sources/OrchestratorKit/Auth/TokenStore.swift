import Foundation
import LocalAuthentication

public enum TokenKind: String, Codable, Sendable {
    /// Personal access token created in the panel (Settings -> API tokens). Starts with `orch_`.
    case personalAccessToken
    /// Short-lived JWT from `POST /api/auth/login`.
    case jwt

    public static func inferred(from token: String) -> TokenKind {
        token.hasPrefix("orch_") ? .personalAccessToken : .jwt
    }

    public var displayName: String {
        switch self {
        case .personalAccessToken: return "Personal access token"
        case .jwt:                 return "Session (JWT)"
        }
    }
}

/// Thread-safe, keychain-backed holder for the bearer token.
///
/// Two modes:
///  * **unprotected** — the token is read from the keychain on first use and cached, so
///    building a request never blocks.
///  * **protected** (app lock on) — the keychain item carries a `SecAccessControl`, so it
///    is *never* read implicitly. `unlock(reason:)` performs the authenticated read and
///    fills the cache; `lock()` empties it again. Until then every request goes out
///    without a bearer header and the UI is behind the lock screen anyway.
public final class TokenStore: @unchecked Sendable {
    public static let shared = TokenStore()

    /// Whether the stored item is biometrically protected. Not a secret, so UserDefaults
    /// is the right home — it must be readable before any authentication happens.
    private static let protectionFlagKey = "orchestrator.token.protected"

    private let keychain: Keychain
    private let defaults: UserDefaults
    private let lock = NSLock()
    private var cachedToken: String?
    private var cachedKind: TokenKind?
    private var loaded = false

    public init(keychain: Keychain = .shared, defaults: UserDefaults = SharedContainer.defaults) {
        self.keychain = keychain
        self.defaults = defaults
    }

    public var isProtected: Bool {
        get { defaults.bool(forKey: Self.protectionFlagKey) }
        set { defaults.set(newValue, forKey: Self.protectionFlagKey) }
    }

    /// True when a token exists on this device, whether or not it is currently readable.
    public var hasStoredToken: Bool {
        if isProtected { return defaults.string(forKey: Self.protectionFlagKey + ".present") != nil }
        return token?.isEmpty == false
    }

    public var token: String? {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeededLocked()
        return cachedToken
    }

    public var kind: TokenKind? {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeededLocked()
        return cachedKind ?? keychain.get(Keychain.Key.apiTokenKind).flatMap(TokenKind.init(rawValue:))
    }

    public var hasToken: Bool { token?.isEmpty == false }

    /// True when the token exists but is currently sealed behind biometrics.
    public var isSealed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isProtected && cachedToken == nil
    }

    // MARK: - Storing

    public func store(_ token: String, kind: TokenKind) throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        try write(trimmed, kind: kind, protected: isProtected)
    }

    private func write(_ token: String, kind: TokenKind, protected: Bool) throws {
        let control = protected ? try Keychain.userPresenceAccessControl() : nil
        try keychain.set(token, for: Keychain.Key.apiToken, accessControl: control)
        try keychain.set(kind.rawValue, for: Keychain.Key.apiTokenKind)

        lock.lock()
        cachedToken = token
        cachedKind = kind
        loaded = true
        isProtected = protected
        defaults.set("1", forKey: Self.protectionFlagKey + ".present")
        lock.unlock()
    }

    /// Re-writes the existing token with or without biometric protection.
    /// Throws if the token is not currently available in memory.
    public func setProtection(_ enabled: Bool) throws {
        lock.lock()
        let current = cachedToken
        let currentKind = cachedKind
        lock.unlock()

        guard let current, !current.isEmpty else { throw KeychainError.itemNotFound }
        try write(current, kind: currentKind ?? TokenKind.inferred(from: current), protected: enabled)
    }

    // MARK: - Locking

    /// Authenticated read. Blocking — call it off the main actor.
    @discardableResult
    public func unlock(reason: String) throws -> String {
        let context = LAContext()
        context.localizedReason = reason
        context.localizedFallbackTitle = ""   // "" hides the software-passcode button; system passcode still works

        let value = try keychain.read(Keychain.Key.apiToken, context: context)
        let kindValue = keychain.get(Keychain.Key.apiTokenKind).flatMap(TokenKind.init(rawValue:))

        lock.lock()
        cachedToken = value
        cachedKind = kindValue ?? TokenKind.inferred(from: value)
        loaded = true
        lock.unlock()
        return value
    }

    /// Drops the in-memory copy so the next unlock has to go through the system again.
    public func lockNow() {
        guard isProtected else { return }
        lock.lock()
        cachedToken = nil
        loaded = false
        lock.unlock()
    }

    public func clear() {
        keychain.remove(Keychain.Key.apiToken)
        keychain.remove(Keychain.Key.apiTokenKind)

        lock.lock()
        cachedToken = nil
        cachedKind = nil
        loaded = true
        isProtected = false
        defaults.removeObject(forKey: Self.protectionFlagKey + ".present")
        lock.unlock()
    }

    private func loadIfNeededLocked() {
        guard !loaded else { return }
        // A protected item must never be read implicitly — that would pop a biometric
        // sheet from whatever thread happened to build a request.
        guard !isProtected else { return }

        loaded = true
        cachedToken = keychain.get(Keychain.Key.apiToken)
        if let raw = keychain.get(Keychain.Key.apiTokenKind) {
            cachedKind = TokenKind(rawValue: raw)
        } else if let token = cachedToken {
            cachedKind = TokenKind.inferred(from: token)
        }
    }
}
