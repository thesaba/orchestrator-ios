import Foundation

enum APIConfig {
    /// Panel root. Every REST path is appended after `apiPath`.
    static let baseURL = URL(string: "https://orchestrator.abesadze.digital")!

    static let apiPath = "/api"

    /// Ordinary JSON calls.
    static let requestTimeout: TimeInterval = 30

    /// Long-running SSE attachments (deploy, provision, artisan, live logs).
    /// The stream stays open until the server sends `done` or the task is cancelled.
    static let streamTimeout: TimeInterval = 60 * 60

    static var apiRoot: URL { baseURL.appendingPathComponent(String(apiPath.dropFirst())) }
}

enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}
