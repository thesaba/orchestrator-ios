import Foundation
import LocalAuthentication
import Security

public enum KeychainError: LocalizedError {
    case encodingFailed
    case accessControlFailed(String)
    case authenticationFailed
    case userCancelled
    case itemNotFound
    case unexpectedStatus(OSStatus)

    public var errorDescription: String? {
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

    public static func map(_ status: OSStatus) -> KeychainError {
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
public final class Keychain: @unchecked Sendable {
    public static let shared = Keychain()

    private let service: String
    private let accessGroup: String?

    /// Defaults come from `SharedContainer`: on iOS that is the bundle identifier and no
    /// access group (unchanged), on the Mac the group shared with the widget extension.
    /// macOS only: whether the data protection keychain (needed for the shared access group)
    /// is usable. It requires a provisioning profile; a build signed without one falls back
    /// to the app's own login-keychain item, so sign-in still works, unshared.
    private let usesDataProtection: Bool

    public init(service: String = SharedContainer.keychainService,
                accessGroup: String? = SharedContainer.keychainAccessGroup) {
        self.service = service
        #if os(macOS)
        let available = Self.dataProtectionKeychainAvailable(service: service, accessGroup: accessGroup)
        self.usesDataProtection = available
        self.accessGroup = available ? accessGroup : nil
        #else
        self.usesDataProtection = false
        self.accessGroup = accessGroup
        #endif
    }

    /// Whether the item can be shared with the widget extension.
    public var isShared: Bool { accessGroup != nil }

    #if os(macOS)
    /// A read-only probe: a lookup answers `errSecMissingEntitlement` when the data protection
    /// keychain is not available to this signature, and "not found" or success when it is.
    private static func dataProtectionKeychainAvailable(service: String, accessGroup: String?) -> Bool {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "orchestrator.keychain.probe",
            kSecUseDataProtectionKeychain as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return SecItemCopyMatching(query as CFDictionary, nil) != errSecMissingEntitlement
    }
    #endif

    /// Requires user presence: biometrics, falling back to the device passcode.
    /// `.userPresence` (rather than `.biometryCurrentSet`) means enrolling a new face or
    /// finger does not invalidate the stored token.
    public static func userPresenceAccessControl() throws -> SecAccessControl {
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
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        #if os(macOS)
        // The legacy file keychain ignores access groups; the data protection keychain
        // behaves like iOS and lets the widget share the item.
        if usesDataProtection {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        #endif
        return query
    }

    /// - Parameter accessControl: when non-nil the item can only be read after a
    ///   successful biometric or passcode check.
    public func set(_ value: String, for key: String, accessControl: SecAccessControl? = nil) throws {
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
    public func get(_ key: String) -> String? {
        try? read(key, context: nil)
    }

    /// Read that may prompt for Face ID / Touch ID / passcode.
    ///
    /// This blocks the calling thread while the system sheet is up, so it must never run
    /// on the main actor — see `TokenStore.unlock(reason:)`.
    public func read(_ key: String, context: LAContext?) throws -> String {
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

    public func remove(_ key: String) {
        SecItemDelete(baseQuery(key) as CFDictionary)
    }
}

extension Keychain {
    public enum Key {
        public static let apiToken = "orchestrator.api.token"
        public static let apiTokenKind = "orchestrator.api.token.kind"
    }
}
