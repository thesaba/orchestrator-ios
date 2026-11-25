import Foundation

/// `GET /api/auth/me` -> { id, email, role, totpEnabled }
/// `GET /api/users`   -> { users: [{ id, email, role, allSitesAccess, createdAt }] }
public struct User: Identifiable, Hashable, Sendable, Codable {
    public var id: Int
    public var email: String
    public var role: String?
    public var totpEnabled: Bool?
    public var allSitesAccess: Bool?
    public var createdAt: Date?

    public var displayName: String { email }

    public var initials: String {
        let parts = email.split(whereSeparator: { $0 == "." || $0 == "@" || $0 == "_" || $0 == "-" })
        let letters = parts.prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    public var isAdmin: Bool { (role ?? "").lowercased().contains("admin") }
}

public struct UsersResponse: Decodable, Sendable {
    public var users: [User]
}

/// `POST /api/auth/login` answers either `{ token }` or `{ requiresTOTP: true }`.
public struct LoginResponse: Decodable, Sendable {
    public var token: String?
    public var requiresTOTP: Bool
    public var message: String?

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(JSONValue.self)
        token = value["token"]?.stringValue ?? value["accessToken"]?.stringValue
        requiresTOTP = value["requiresTOTP"]?.boolValue
            ?? value["requiresTotp"]?.boolValue
            ?? value["requires2FA"]?.boolValue
            ?? false
        message = value["message"]?.stringValue ?? value["error"]?.stringValue
    }
}

public struct LoginRequest: Encodable, Sendable {
    public var email: String
    public var password: String
    public var totpCode: String?

    public init(email: String, password: String, totpCode: String? = nil) {
        self.email = email
        self.password = password
        self.totpCode = totpCode
    }
}

/// `GET /api/tokens` -> { tokens: [...] }. The secret itself is only returned on create.
public struct APIToken: Identifiable, Hashable, Sendable, Codable {
    public var id: Int
    public var name: String
    public var tokenPrefix: String?
    public var lastUsedAt: Date?
    public var expiresAt: Date?
    public var createdAt: Date?
}

public struct APITokensResponse: Decodable, Sendable {
    public var tokens: [APIToken]
}
