import Foundation
import LocalAuthentication
import Security

enum KeychainError: LocalizedError {
    case encodingFailed
    case accessControlFailed(String)
    case authenticationFailed
    case userCancelled
    case itemNotFound
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Could not encode the value for the keychain."
        case .accessControlFailed(let message):
            return "Could not set up biometric protection: \(message)"
        case .authenticationFailed:
            return "Authentication failed."
        case .userCancelled:
            return "Cancelled."
        case .itemNotFound:
            return "Nothing is stored on this device."
        case .unexpectedStatus(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "status \(status)"
            return "Keychain error: \(message)"
        }
    }

    static func map(_ status: OSStatus) -> KeychainError {
        switch status {
        case errSecItemNotFound:      return .itemNotFound
        case errSecUserCanceled:      return .userCancelled
        case errSecAuthFailed:        return .authenticationFailed
        default:                      return .unexpectedStatus(status)
        }
    }
}

/// Small wrapper around the generic-password keychain class.
///
/// The API token lives here and nowhere else — never in UserDefaults, never in logs.
/// When app lock is on, the item additionally carries a `SecAccessControl` so iOS itself
/// refuses to hand the token over without Face ID / Touch ID / the device passcode.
final class Keychain: @unchecked Sendable {
    static let shared = Keychain()

    private let service: String

    init(service: String = Bundle.main.bundleIdentifier ?? "digital.abesadze.Orchestrator") {
        self.service = service
    }

    /// Requires user presence: biometrics, falling back to the device passcode.
    /// `.userPresence` (rather than `.biometryCurrentSet`) means enrolling a new face or
    /// finger does not invalidate the stored token.
    static func userPresenceAccessControl() throws -> SecAccessControl {
        var error: Unmanaged<CFError>?
        guard let control = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .userPresence,
            &error
        ) else {
            let message = (error?.takeRetainedValue() as Error?)?.localizedDescription ?? "unknown"
            throw KeychainError.accessControlFailed(message)
        }
        return control
    }

    private func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }

    /// - Parameter accessControl: when non-nil the item can only be read after a
    ///   successful biometric or passcode check.
    func set(_ value: String, for key: String, accessControl: SecAccessControl? = nil) throws {
        guard let data = value.data(using: .utf8) else { throw KeychainError.encodingFailed }

        // Removing a protected item does not itself require authentication.
        SecItemDelete(baseQuery(key) as CFDictionary)

        var insert = baseQuery(key)
        insert[kSecValueData as String] = data
        if let accessControl {
            insert[kSecAttrAccessControl as String] = accessControl
            // A fresh context stops iOS prompting during the write itself.
            insert[kSecUseAuthenticationContext as String] = LAContext()
        } else {
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        }

        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.map(status) }
    }

    /// Non-throwing read for unprotected items.
    func get(_ key: String) -> String? {
        try? read(key, context: nil)
    }

    /// Read that may prompt for Face ID / Touch ID / passcode.
    ///
    /// This blocks the calling thread while the system sheet is up, so it must never run
    /// on the main actor — see `TokenStore.unlock(reason:)`.
    func read(_ key: String, context: LAContext?) throws -> String {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        if let context {
            query[kSecUseAuthenticationContext as String] = context
        }

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { throw KeychainError.map(status) }
        guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.itemNotFound
        }
        return value
    }

    func remove(_ key: String) {
        SecItemDelete(baseQuery(key) as CFDictionary)
    }
}

extension Keychain {
    enum Key {
        static let apiToken = "orchestrator.api.token"
        static let apiTokenKind = "orchestrator.api.token.kind"
    }
}
