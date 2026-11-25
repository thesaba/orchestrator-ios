import AppKit
import OrchestratorKit

/// Deep links into the web panel, for everything the Mac app shows but does not do itself.
enum WebPanel {
    enum Destination: Hashable {
        case home
        case site(id: Int)
        case server(id: Int)
        case serverAlerts
        case tokens
    }

    static func url(for destination: Destination) -> URL {
        let base = APIConfig.baseURL
        switch destination {
        case .home:              return base
        case .site(let id):      return base.appending(path: "sites/\(id)")
        case .server(let id):    return base.appending(path: "servers/\(id)")
        case .serverAlerts:
            var components = URLComponents(url: base.appending(path: "servers"), resolvingAgainstBaseURL: false)
            components?.queryItems = [URLQueryItem(name: "tab", value: "alerts")]
            return components?.url ?? base
        case .tokens:            return base.appending(path: "settings")
        }
    }

    static func open(_ destination: Destination) {
        NSWorkspace.shared.open(url(for: destination))
    }
}
