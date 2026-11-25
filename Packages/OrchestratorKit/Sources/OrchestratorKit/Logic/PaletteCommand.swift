import Foundation

/// One entry of the command palette. Pure data; the Mac app decides how to run it.
public struct PaletteCommand: Sendable, Hashable, Identifiable {
    public enum Group: Int, Sendable, Hashable, CaseIterable, Comparable {
        case recent, actions, servers, open

        public var title: String {
            switch self {
            case .recent:  return "Recent"
            case .actions: return "Actions"
            case .servers: return "Servers"
            case .open:    return "Open"
            }
        }

        public static func < (lhs: Group, rhs: Group) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public enum Kind: Sendable, Hashable {
        case deploy(siteID: Int)
        case rollback(siteID: Int)
        case clearCache(siteID: Int)
        case maintenance(siteID: Int, enable: Bool)
        case restartQueue(siteID: Int)
        case artisan(siteID: Int)
        case renewCertificate(siteID: Int)
        case ssh(serverID: Int)
        case siteLogs(siteID: Int)
        case lastDeployLog(siteID: Int)
        case openSite(siteID: Int)
        case openServer(serverID: Int)

        public var siteID: Int? {
            switch self {
            case .deploy(let id), .rollback(let id), .clearCache(let id), .restartQueue(let id),
                 .artisan(let id), .renewCertificate(let id), .siteLogs(let id), .lastDeployLog(let id),
                 .openSite(let id):
                return id
            case .maintenance(let id, _):
                return id
            case .ssh, .openServer:
                return nil
            }
        }

        /// Whether running it changes production (and therefore needs a confirmation).
        public var changesProduction: Bool {
            switch self {
            case .deploy, .rollback, .clearCache, .maintenance, .restartQueue, .artisan, .renewCertificate:
                return true
            case .ssh, .siteLogs, .lastDeployLog, .openSite, .openServer:
                return false
            }
        }

        /// Rollback and maintenance mode also need Touch ID or the account password.
        /// (Destructive Artisan commands are decided when the command is chosen.)
        public var requiresAuthentication: Bool {
            switch self {
            case .rollback, .maintenance: return true
            default:                      return false
            }
        }

        /// Deploys can be run on a chosen branch or ref (Option-Return).
        public var acceptsRef: Bool {
            if case .deploy = self { return true }
            return false
        }
    }

    /// Stable across refreshes; used for recents and selection.
    public var id: String
    public var kind: Kind
    public var group: Group
    /// "Deploy citynet.ge".
    public var title: String
    /// Secondary text on the same line: "main", "config, routes, views".
    public var detail: String
    /// SF Symbol of the 28 pt icon tile.
    public var symbol: String
    /// The words fuzzy matching runs over (verb and target).
    public var searchText: String

    public var requiresAuthentication: Bool { kind.requiresAuthentication }

    public init(id: String, kind: Kind, group: Group, title: String, detail: String, symbol: String, searchText: String) {
        self.id = id
        self.kind = kind
        self.group = group
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.searchText = searchText
    }
}
