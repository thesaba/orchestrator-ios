import Foundation

/// `orchestrator://` links into the Mac app, for Shortcuts, scripts and widgets.
///
/// A deep link only opens things; it never runs an action that changes production.
///
/// | URL | Opens |
/// |---|---|
/// | `orchestrator://overview` (also `servers`, `sites`, `alerts`) | the popover on that segment |
/// | `orchestrator://settings` | Settings |
/// | `orchestrator://site/12/log` | the deploy log window of site 12 |
/// | `orchestrator://site/12/logs` | the Laravel log of site 12 |
/// | `orchestrator://site/12` | site 12's page in the main window |
/// | `orchestrator://site/12/config` (also `overview`, `deploys`, `ssl`, `workers`, `artisan`, `files`, `database`, `security`) | that tab of site 12's page |
/// | `orchestrator://server/5` | server 5's page in the main window |
public enum DeepLink: Sendable, Hashable {
    public enum Segment: String, Sendable, CaseIterable {
        case overview, servers, sites, alerts
    }

    case popover(Segment)
    case settings
    case deployLog(siteID: Int)
    case siteLogs(siteID: Int)
    case site(siteID: Int)
    /// One tab of a site's page; `tab` is one of `SiteTabName`.
    case siteTab(siteID: Int, tab: String)
    case server(serverID: Int)

    /// The site-page tabs a link can name.
    public static let siteTabNames: Set<String> = ["overview", "deploys", "config", "ssl", "workers", "artisan", "files", "database", "security"]

    public static let scheme = "orchestrator"

    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme, let host = url.host()?.lowercased() else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }

        if let segment = Segment(rawValue: host), parts.isEmpty {
            self = .popover(segment)
            return
        }
        switch (host, parts.count) {
        case ("settings", 0):
            self = .settings
        case ("server", 1):
            guard let id = Int(parts[0]), id > 0 else { return nil }
            self = .server(serverID: id)
        case ("site", 1):
            guard let id = Int(parts[0]), id > 0 else { return nil }
            self = .site(siteID: id)
        case ("site", 2):
            guard let id = Int(parts[0]), id > 0 else { return nil }
            switch parts[1].lowercased() {
            case "log":  self = .deployLog(siteID: id)
            case "logs": self = .siteLogs(siteID: id)
            case let tab where Self.siteTabNames.contains(tab):
                self = .siteTab(siteID: id, tab: tab)
            default:     return nil
            }
        default:
            return nil
        }
    }

    public var url: URL {
        let path: String
        switch self {
        case .popover(let segment):     path = segment.rawValue
        case .settings:                 path = "settings"
        case .deployLog(let id):        path = "site/\(id)/log"
        case .siteLogs(let id):         path = "site/\(id)/logs"
        case .site(let id):             path = "site/\(id)"
        case .siteTab(let id, let tab): path = "site/\(id)/\(tab)"
        case .server(let id):           path = "server/\(id)"
        }
        // Built from known parts only, so the force unwrap cannot fail.
        return URL(string: "\(Self.scheme)://\(path)")!
    }
}
