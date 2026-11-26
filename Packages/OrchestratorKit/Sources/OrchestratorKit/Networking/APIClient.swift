import Foundation
import OSLog

/// Placeholder for endpoints whose body we do not care about.
public struct EmptyResponse: Decodable, Sendable {
    public init() {}
    public init(from decoder: Decoder) throws {}
}

/// One server-sent event.
public struct SSEEvent: Sendable, Hashable {
    public var event: String?
    public var id: String?
    public var data: String
}

/// The single place where HTTP happens.
///
/// Responsibilities: base URL, bearer header, JSON coding, uniform error mapping,
/// and SSE streaming. Feature code never touches `URLSession` directly.
public final class APIClient: @unchecked Sendable {
    public static let shared = APIClient()

    private let baseURL: URL
    private let tokenStore: TokenStore
    /// When set, sent instead of the stored token (the Mac app's separate admin session).
    private let fixedToken: String?
    private let session: URLSession
    private let streamSession: URLSession
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Orchestrator", category: "api")

    public init(baseURL: URL = APIConfig.baseURL, tokenStore: TokenStore = .shared, fixedToken: String? = nil) {
        self.baseURL = baseURL
        self.tokenStore = tokenStore
        self.fixedToken = fixedToken

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = APIConfig.requestTimeout
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration)

        let streamConfiguration = URLSessionConfiguration.default
        streamConfiguration.timeoutIntervalForRequest = APIConfig.streamTimeout
        streamConfiguration.timeoutIntervalForResource = APIConfig.streamTimeout
        streamConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.streamSession = URLSession(configuration: streamConfiguration)
    }

    // MARK: - Coding

    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = DateParsing.decodingStrategy
        return decoder
    }()

    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = DateParsing.encodingStrategy
        return encoder
    }()

    // MARK: - Public JSON API

    public func get<T: Decodable>(_ path: String, query: [URLQueryItem] = [], as type: T.Type = T.self) async throws -> T {
        let data = try await perform(.get, path, query: query)
        return try decode(data, as: type, path: path)
    }

    public func post<T: Decodable>(_ path: String, body: (any Encodable)? = nil, query: [URLQueryItem] = [], as type: T.Type = T.self) async throws -> T {
        let data = try await perform(.post, path, query: query, body: try encodeBody(body))
        return try decode(data, as: type, path: path)
    }

    public func put<T: Decodable>(_ path: String, body: (any Encodable)? = nil, query: [URLQueryItem] = [], as type: T.Type = T.self) async throws -> T {
        let data = try await perform(.put, path, query: query, body: try encodeBody(body))
        return try decode(data, as: type, path: path)
    }

    public func patch<T: Decodable>(_ path: String, body: (any Encodable)? = nil, query: [URLQueryItem] = [], as type: T.Type = T.self) async throws -> T {
        let data = try await perform(.patch, path, query: query, body: try encodeBody(body))
        return try decode(data, as: type, path: path)
    }

    public func delete<T: Decodable>(_ path: String, body: (any Encodable)? = nil, query: [URLQueryItem] = [], as type: T.Type = T.self) async throws -> T {
        let data = try await perform(.delete, path, query: query, body: try encodeBody(body))
        return try decode(data, as: type, path: path)
    }

    /// Fire-and-check variants for endpoints whose response body is irrelevant.
    @discardableResult
    public func send(_ method: HTTPMethod, _ path: String, body: (any Encodable)? = nil, query: [URLQueryItem] = []) async throws -> Data {
        try await perform(method, path, query: query, body: try encodeBody(body))
    }

    /// Raw bytes, for downloads (database backups, file manager downloads).
    public func download(_ path: String, query: [URLQueryItem] = []) async throws -> (Data, String?) {
        let request = try makeRequest(.get, path, query: query, body: nil, contentType: nil, timeout: APIConfig.streamTimeout)
        do {
            let (data, response) = try await session.data(for: request)
            try validate(response, data: data, path: path)
            let filename = (response as? HTTPURLResponse)
                .flatMap { $0.value(forHTTPHeaderField: "Content-Disposition") }
                .flatMap(Self.filename(fromContentDisposition:))
            return (data, filename)
        } catch {
            throw APIError.wrap(error)
        }
    }

    /// `multipart/form-data` upload of whole files (the file manager's upload route).
    @discardableResult
    public func upload(_ path: String, query: [URLQueryItem] = [], files: [(name: String, data: Data)]) async throws -> Data {
        let boundary = "OrchestratorBoundary-\(UUID().uuidString)"
        var body = Data()
        for file in files {
            let safeName = file.name.replacingOccurrences(of: "\"", with: "_")
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(safeName)\"\r\n".utf8))
            body.append(Data("Content-Type: application/octet-stream\r\n\r\n".utf8))
            body.append(file.data)
            body.append(Data("\r\n".utf8))
        }
        body.append(Data("--\(boundary)--\r\n".utf8))
        let request = try makeRequest(.post, path, query: query, body: body,
                                      contentType: "multipart/form-data; boundary=\(boundary)",
                                      timeout: APIConfig.streamTimeout)
        do {
            let (data, response) = try await session.data(for: request)
            try validate(response, data: data, path: path)
            return data
        } catch {
            throw APIError.wrap(error)
        }
    }

    // MARK: - Server-sent events

    /// Attaches to an SSE endpoint. Cancelling the consuming task closes the connection.
    ///
    /// Unlike the browser's `EventSource`, `URLSession` lets us set `Authorization`
    /// on a streaming request, so the bearer token is used directly — no query-string token.
    public func events(_ path: String, query: [URLQueryItem] = []) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [weak self] in
                guard let self else { return continuation.finish() }
                do {
                    var request = try self.makeRequest(.get, path, query: query, body: nil, contentType: nil, timeout: APIConfig.streamTimeout)
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

                    let (bytes, response) = try await self.streamSession.bytes(for: request)
                    try self.validate(response, data: Data(), path: path)

                    // Parse bytes directly: `bytes.lines` drops the blank lines that end SSE events.
                    var parser = SSEParser()
                    for try await byte in bytes {
                        if let event = parser.feed(byte) {
                            try Task.checkCancellation()
                            continuation.yield(event)
                        }
                    }
                    if let event = parser.finish() { continuation.yield(event) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: APIError.wrap(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Plumbing

    private func perform(_ method: HTTPMethod, _ path: String, query: [URLQueryItem], body: Data? = nil) async throws -> Data {
        let request = try makeRequest(method, path, query: query, body: body,
                                      contentType: body == nil ? nil : "application/json",
                                      timeout: APIConfig.requestTimeout)
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            logger.debug("\(method.rawValue, privacy: .public) \(path, privacy: .public) -> \(status, privacy: .public)")
            try validate(response, data: data, path: path)
            return data
        } catch {
            throw APIError.wrap(error)
        }
    }

    private func makeRequest(_ method: HTTPMethod,
                             _ path: String,
                             query: [URLQueryItem],
                             body: Data?,
                             contentType: String?,
                             timeout: TimeInterval) throws -> URLRequest {
        // With app lock on, the token only exists in memory after a successful unlock.
        // Sending an unauthenticated request would come back 401 and look like an expired
        // credential, so fail fast with something the UI can recognise instead.
        if fixedToken == nil, tokenStore.isSealed { throw APIError.locked }

        let normalized = path.hasPrefix("/") ? path : "/" + path
        guard var components = URLComponents(string: baseURL.absoluteString + APIConfig.apiPath + normalized) else {
            throw APIError.invalidURL(path)
        }
        if !query.isEmpty {
            components.queryItems = (components.queryItems ?? []) + query
        }
        guard let url = components.url else { throw APIError.invalidURL(path) }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method.rawValue
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        if let token = fixedToken ?? tokenStore.token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func encodeBody(_ body: (any Encodable)?) throws -> Data? {
        guard let body else { return nil }
        do {
            return try Self.encoder.encode(body)
        } catch {
            throw APIError.unknown(error)
        }
    }

    private func decode<T: Decodable>(_ data: Data, as type: T.Type, path: String) throws -> T {
        if type == EmptyResponse.self {
            return EmptyResponse() as! T
        }
        if data.isEmpty {
            throw APIError.decoding(path: path, underlying: DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "Empty response body")))
        }
        do {
            return try Self.decoder.decode(type, from: data)
        } catch {
            #if DEBUG
            let preview = String(data: data.prefix(600), encoding: .utf8) ?? "<binary>"
            logger.error("Decoding \(path, privacy: .public) failed: \(String(describing: error), privacy: .public)\n\(preview, privacy: .private)")
            #endif
            throw APIError.decoding(path: path, underlying: error)
        }
    }

    private func validate(_ response: URLResponse, data: Data, path: String) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard !(200..<300).contains(http.statusCode) else { return }

        let message = Self.errorMessage(from: data)
        switch http.statusCode {
        case 401:
            // A 401 on the admin session ends only that session, never the main sign-in.
            if fixedToken == nil { UnauthorizedSignal.shared.fire() }
            throw APIError.unauthorized(message)
        case 403:
            throw APIError.forbidden(message)
        case 404:
            throw APIError.notFound(message)
        default:
            throw APIError.http(status: http.statusCode, message: message)
        }
    }

    /// Pulls a human message out of whatever error envelope the server used.
    public static func errorMessage(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        if let value = try? JSONDecoder().decode(JSONValue.self, from: data) {
            // `{ error: "Query failed", details: "Unknown column…" }`: the details say why.
            if let error = value["error"]?.stringValue, let details = value["details"]?.stringValue, !details.isEmpty {
                return "\(error): \(details)"
            }
            for key in ["error", "message", "msg", "detail", "reason"] {
                if let candidate = value[key] {
                    if let text = candidate.stringValue, !text.isEmpty { return text }
                    if let nested = candidate["message"]?.stringValue { return nested }
                }
            }
        }
        if let text = String(data: data.prefix(300), encoding: .utf8),
           !text.isEmpty, !text.hasPrefix("<") {
            return text
        }
        return nil
    }

    private static func filename(fromContentDisposition header: String) -> String? {
        for part in header.split(separator: ";") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            guard trimmed.lowercased().hasPrefix("filename=") else { continue }
            return trimmed
                .dropFirst("filename=".count)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        return nil
    }
}

// MARK: - Path helpers

public enum APIPath {
    /// Percent-encodes a dynamic path segment (filenames, file-manager paths, ids).
    public static func segment(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#")))
            ?? value
    }
}
