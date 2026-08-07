import Foundation

/// `GET /api/auth/me` -> { id, email, role, totpEnabled }
/// `GET /api/users`   -> { users: [{ id, email, role, allSitesAccess, createdAt }] }
struct User: Identifiable, Hashable, Sendable, Codable {
    var id: Int
    var email: String
    var role: String?
    var totpEnabled: Bool?
    var allSitesAccess: Bool?
    var createdAt: Date?

    var displayName: String { email }

    var initials: String {
        let parts = email.split(whereSeparator: { $0 == "." || $0 == "@" || $0 == "_" || $0 == "-" })
        let letters = parts.prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    var isAdmin: Bool { (role ?? "").lowercased().contains("admin") }
}

struct UsersResponse: Decodable, Sendable {
    var users: [User]
}

/// `POST /api/auth/login` answers either `{ token }` or `{ requiresTOTP: true }`.
struct LoginResponse: Decodable, Sendable {
    var token: String?
    var requiresTOTP: Bool
    var message: String?

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(JSONValue.self)
        token = value["token"]?.stringValue ?? value["accessToken"]?.stringValue
        requiresTOTP = value["requiresTOTP"]?.boolValue
            ?? value["requiresTotp"]?.boolValue
            ?? value["requires2FA"]?.boolValue
            ?? false
        message = value["message"]?.stringValue ?? value["error"]?.stringValue
    }
}

struct LoginRequest: Encodable, Sendable {
    var email: String
    var password: String
    var totpCode: String?
}

/// `GET /api/tokens` -> { tokens: [...] }. The secret itself is only returned on create.
struct APIToken: Identifiable, Hashable, Sendable, Codable {
    var id: Int
    var name: String
    var tokenPrefix: String?
    var lastUsedAt: Date?
    var expiresAt: Date?
    var createdAt: Date?
}

struct APITokensResponse: Decodable, Sendable {
    var tokens: [APIToken]
}
