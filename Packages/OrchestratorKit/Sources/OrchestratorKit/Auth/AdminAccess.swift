import Foundation
import Observation

/// A second, short-lived sign-in with email, password and 2FA, for what the panel refuses
/// to personal access tokens: the terminal, saved scripts and free commands.
///
/// The JWT lives in memory only (never the Keychain) and nothing is kept of the password.
/// Server terminals, scripts and commands also need a 2FA step-up, which the panel grants
/// to this one JWT for 15 minutes.
@MainActor
@Observable
public final class AdminAccess {
    public enum SignInResult: Equatable { case signedIn, needsCode }

    public private(set) var email: String?
    public private(set) var expiresAt: Date?
    public private(set) var elevatedUntil: Date?
    /// Whether the account has 2FA at all; step-up is impossible without it.
    public private(set) var totpEnabled: Bool?

    private var token: String?
    @ObservationIgnored public private(set) var api: OrchestratorAPI?
    @ObservationIgnored private let baseURL: URL

    public init(baseURL: URL = APIConfig.baseURL) {
        self.baseURL = baseURL
    }

    public var isSignedIn: Bool {
        guard token != nil, let expiresAt else { return token != nil }
        return expiresAt > .now
    }

    public func isElevated(now: Date = .now) -> Bool {
        guard isSignedIn, let elevatedUntil else { return false }
        return elevatedUntil > now
    }

    // MARK: - Sign in

    /// `POST /api/auth/login`. Answers `.needsCode` when the account asks for a 2FA code.
    public func signIn(email: String, password: String, totpCode: String?) async throws -> SignInResult {
        let client = APIClient(baseURL: baseURL, fixedToken: "")
        let code = totpCode?.trimmingCharacters(in: .whitespaces)
        let response: LoginResponse = try await client.post(
            "/auth/login",
            body: LoginRequest(email: email.trimmingCharacters(in: .whitespaces), password: password,
                               totpCode: (code?.isEmpty ?? true) ? nil : code))
        if response.requiresTOTP, response.token == nil { return .needsCode }
        guard let jwt = response.token, !jwt.isEmpty else {
            throw APIError.http(status: 200, message: response.message ?? "The panel did not return a session.")
        }
        adopt(jwt: jwt, email: email)
        await refreshElevation()
        return .signedIn
    }

    func adopt(jwt: String, email: String?) {
        token = jwt
        self.email = email
        expiresAt = Self.expiry(ofJWT: jwt)
        elevatedUntil = nil
        api = OrchestratorAPI(client: APIClient(baseURL: baseURL, fixedToken: jwt))
    }

    public func signOut() {
        token = nil
        api = nil
        email = nil
        expiresAt = nil
        elevatedUntil = nil
        totpEnabled = nil
    }

    // MARK: - 2FA step-up

    private struct ElevationState: Decodable {
        var totpEnabled: Bool?
        var elevated: Bool
        var until: Date?
    }

    private struct ElevationRequest: Encodable { var code: String }

    /// `GET /api/fleet/elevate` — whether this session is stepped up, and until when.
    public func refreshElevation() async {
        guard let api else { return }
        if let state = try? await api.client.get("/fleet/elevate", as: ElevationState.self) {
            totpEnabled = state.totpEnabled
            elevatedUntil = state.elevated ? state.until : nil
        }
    }

    /// `POST /api/fleet/elevate { code }` — steps this session up for 15 minutes.
    public func elevate(code: String) async throws {
        guard let api else { throw APIError.unauthorized("Sign in with your password first.") }
        let state = try await api.client.post("/fleet/elevate",
                                              body: ElevationRequest(code: code.filter { !$0.isWhitespace }),
                                              as: ElevationState.self)
        totpEnabled = state.totpEnabled
        elevatedUntil = state.elevated ? state.until : nil
    }

    // MARK: - Terminal WebSockets

    /// `wss://…/api/terminal/:siteId?token=JWT` — a shell in the site's folder.
    public func siteTerminalURL(siteID: Int) -> URL? {
        socketURL(path: "/terminal/\(siteID)", query: [])
    }

    /// `wss://…/api/terminal/fleet/term/:serverId?token=JWT&cols&rows` — needs the step-up.
    public func serverTerminalURL(serverID: Int, cols: Int, rows: Int) -> URL? {
        socketURL(path: "/terminal/fleet/term/\(serverID)",
                  query: [URLQueryItem(name: "cols", value: String(cols)), URLQueryItem(name: "rows", value: String(rows))])
    }

    private func socketURL(path: String, query: [URLQueryItem]) -> URL? {
        guard let token else { return nil }
        return Self.socketURL(baseURL: baseURL, path: path, token: token, query: query)
    }

    /// Builds a WebSocket URL on the API with the JWT in the query string, the way the
    /// panel's own terminals connect (a browser cannot set headers on a WebSocket).
    nonisolated public static func socketURL(baseURL: URL, path: String, token: String, query: [URLQueryItem]) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = components.scheme == "http" ? "ws" : "wss"
        components.path = APIConfig.apiPath + path
        components.queryItems = [URLQueryItem(name: "token", value: token)] + query
        return components.url
    }

    /// The `exp` claim of a JWT, without verifying it (the panel does that).
    nonisolated public static func expiry(ofJWT jwt: String) -> Date? {
        let parts = jwt.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var base64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = object["exp"] as? Double else { return nil }
        return Date(timeIntervalSince1970: exp)
    }
}
