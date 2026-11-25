import Foundation

public enum APIError: LocalizedError {
    case invalidURL(String)
    /// App lock is on and the token has not been released by the Keychain yet.
    /// Distinct from `unauthorized` on purpose: nothing was sent and nothing is wrong.
    case locked
    case unauthorized(String?)
    case forbidden(String?)
    case notFound(String?)
    case http(status: Int, message: String?)
    case decoding(path: String, underlying: Error)
    case transport(URLError)
    case streamFailed(String)
    case cancelled
    case unknown(Error)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let path):
            return "Could not build a valid URL for \(path)."
        case .locked:
            return "The app is locked."
        case .unauthorized(let message):
            return message ?? "Your session is no longer valid. Sign in again."
        case .forbidden(let message):
            return message ?? "You do not have permission to do that."
        case .notFound(let message):
            return message ?? "Not found."
        case .http(let status, let message):
            if let message, !message.isEmpty { return message }
            return "Request failed with status \(status)."
        case .decoding(let path, _):
            return "The server sent an unexpected response for \(path)."
        case .transport(let error):
            switch error.code {
            case .notConnectedToInternet: return "No internet connection."
            case .timedOut:               return "The request timed out."
            case .cannotFindHost,
                 .cannotConnectToHost:    return "Cannot reach the Orchestrator server."
            case .networkConnectionLost:  return "The network connection was lost."
            default:                      return error.localizedDescription
            }
        case .streamFailed(let message):
            return message
        case .cancelled:
            return "Cancelled."
        case .unknown(let error):
            return error.localizedDescription
        }
    }

    /// Extra detail worth showing in a disclosure row but not in the headline.
    public var debugDetail: String? {
        switch self {
        case .decoding(let path, let underlying): return "\(path)\n\(underlying)"
        case .unknown(let error): return String(describing: error)
        default: return nil
        }
    }

    public var isUnauthorized: Bool {
        if case .unauthorized = self { return true }
        return false
    }

    public var isLocked: Bool {
        if case .locked = self { return true }
        return false
    }

    public var isCancellation: Bool {
        if case .cancelled = self { return true }
        return false
    }

    /// Normalises anything thrown inside the networking layer into an `APIError`.
    public static func wrap(_ error: Error) -> APIError {
        if let api = error as? APIError { return api }
        if error is CancellationError { return .cancelled }
        if let urlError = error as? URLError {
            return urlError.code == .cancelled ? .cancelled : .transport(urlError)
        }
        return .unknown(error)
    }
}
