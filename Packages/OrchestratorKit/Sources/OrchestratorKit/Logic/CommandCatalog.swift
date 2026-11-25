import Foundation

/// Builds the palette's commands from the site list and fleet servers, and ranks them.
public enum CommandCatalog {
    public struct Section: Sendable, Hashable, Identifiable {
        public var group: PaletteCommand.Group
        public var commands: [PaletteCommand]
        public var id: PaletteCommand.Group { group }
    }

    // MARK: - Building

    public static func commands(sites: [SiteListing], servers: [FleetServer]) -> [PaletteCommand] {
        var result: [PaletteCommand] = []
        for site in sites where !site.disabled {
            result += siteCommands(site)
        }
        for server in servers {
            result += serverCommands(server, sites: sites)
        }
        return result
    }

    static func siteCommands(_ site: SiteListing) -> [PaletteCommand] {
        let domain = site.domain
        let names = site.name.caseInsensitiveCompare(domain) == .orderedSame ? domain : "\(domain) \(site.name)"
        func make(_ key: String, _ kind: PaletteCommand.Kind, _ group: PaletteCommand.Group,
                  verb: String, title: String, detail: String, symbol: String) -> PaletteCommand {
            PaletteCommand(id: "\(key):\(site.id)", kind: kind, group: group, title: title,
                           detail: detail, symbol: symbol, searchText: "\(verb) \(names)")
        }

        var commands = [
            make("deploy", .deploy(siteID: site.id), .actions, verb: "deploy",
                 title: "Deploy \(domain)", detail: site.branch ?? "default branch", symbol: "arrow.up"),
            make("rollback", .rollback(siteID: site.id), .actions, verb: "roll back rollback revert",
                 title: "Roll back \(domain)", detail: "to the previous release", symbol: "arrow.uturn.backward"),
            make("cache", .clearCache(siteID: site.id), .actions, verb: "clear cache optimize",
                 title: "Clear cache · \(domain)", detail: "config, routes, views", symbol: "trash"),
            site.maintenanceMode
                ? make("maintenance-off", .maintenance(siteID: site.id, enable: false), .actions,
                       verb: "maintenance mode off up", title: "Maintenance mode off · \(domain)",
                       detail: "site comes back for visitors", symbol: "checkmark.circle")
                : make("maintenance-on", .maintenance(siteID: site.id, enable: true), .actions,
                       verb: "maintenance mode on down", title: "Maintenance mode on · \(domain)",
                       detail: "site goes offline for visitors", symbol: "exclamationmark.triangle"),
            make("queue", .restartQueue(siteID: site.id), .actions, verb: "restart queue workers",
                 title: "Restart queue · \(domain)", detail: "workers restart after their current job",
                 symbol: "arrow.clockwise"),
            make("artisan", .artisan(siteID: site.id), .actions, verb: "run artisan command",
                 title: "Run Artisan command · \(domain)", detail: "choose a command", symbol: "chevron.left.forwardslash.chevron.right")
        ]
        if site.sslEnabled {
            commands.append(make("ssl", .renewCertificate(siteID: site.id), .actions, verb: "renew ssl certificate",
                                 title: "Renew SSL · \(domain)", detail: "certbot renew", symbol: "lock.rotation"))
        }

        commands.append(make("logs", .siteLogs(siteID: site.id), .open, verb: "site logs laravel log",
                             title: "Site logs · \(domain)", detail: "Laravel log", symbol: "doc.text.magnifyingglass"))
        if let last = site.latestDeployment {
            commands.append(make("lastlog", .lastDeployLog(siteID: site.id), .open, verb: "last deploy log",
                                 title: "Last deploy log · \(domain)", detail: deployDetail(last),
                                 symbol: "text.alignleft"))
        }
        commands.append(make("web", .openSite(siteID: site.id), .open, verb: "open web panel",
                             title: "Open \(domain) in the web panel", detail: "browser", symbol: "safari"))
        return commands
    }

    static func serverCommands(_ server: FleetServer, sites: [SiteListing]) -> [PaletteCommand] {
        let hosted = sites.filter { site in
            site.serverId == server.id || (site.serverId == nil && server.isLocal)
        }
        var sshDetail = "opens Terminal"
        if let first = hosted.first {
            let more = hosted.count > 1 ? " +\(hosted.count - 1)" : ""
            sshDetail = "hosts \(first.domain)\(more) · opens Terminal"
        }
        let siteWords = hosted.map(\.domain).joined(separator: " ")
        var commands: [PaletteCommand] = []
        if server.isLocal || server.hasSsh || server.host != nil {
            commands.append(PaletteCommand(
                id: "ssh:\(server.id)", kind: .ssh(serverID: server.id), group: .servers,
                title: "SSH into \(server.name)", detail: sshDetail, symbol: "apple.terminal",
                searchText: "ssh terminal \(server.name) \(siteWords)"))
        }
        commands.append(PaletteCommand(
            id: "server-web:\(server.id)", kind: .openServer(serverID: server.id), group: .open,
            title: "Open \(server.name) in the web panel", detail: server.location ?? "browser",
            symbol: "server.rack", searchText: "open web panel server \(server.name)"))
        return commands
    }

    static func deployDetail(_ deployment: DeploymentRecord) -> String {
        var parts: [String] = []
        if let date = deployment.createdAt {
            parts.append(date.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
        }
        switch deployment.status {
        case "success": parts.append("succeeded")
        case "failed":  parts.append("failed")
        case "running": parts.append("running")
        default:        parts.append(deployment.status)
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Ranking

    /// Sections in display order. With an empty query: the recently used commands. Otherwise
    /// every match, recent ones boosted, groups ordered by their best match.
    public static func rank(_ commands: [PaletteCommand], query: String, recent: [String],
                            emptyLimit: Int = 8, limit: Int = 60) -> [Section] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let recentRank = Dictionary(recent.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })

        if trimmed.isEmpty {
            let byID = Dictionary(commands.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            var recents = recent.compactMap { byID[$0] }.prefix(emptyLimit).map { command -> PaletteCommand in
                var copy = command
                copy.group = .recent
                return copy
            }
            if recents.isEmpty {
                recents = Array(commands.filter { $0.group == .actions }.prefix(emptyLimit))
                return recents.isEmpty ? [] : [Section(group: .actions, commands: recents)]
            }
            return [Section(group: .recent, commands: recents)]
        }

        var scored: [(command: PaletteCommand, score: Double)] = []
        for command in commands {
            guard let base = FuzzyMatcher.score(trimmed, in: command.searchText) else { continue }
            let boost = recentRank[command.id].map { max(0, 4 - Double($0) * 0.5) } ?? 0
            scored.append((command, base + boost))
        }
        scored.sort { $0.score > $1.score }
        scored = Array(scored.prefix(limit))

        var best: [PaletteCommand.Group: Double] = [:]
        var grouped: [PaletteCommand.Group: [PaletteCommand]] = [:]
        for entry in scored {
            best[entry.command.group] = max(best[entry.command.group] ?? -.infinity, entry.score)
            grouped[entry.command.group, default: []].append(entry.command)
        }
        return grouped.keys
            .sorted { (best[$0] ?? 0, -$0.rawValue) > (best[$1] ?? 0, -$1.rawValue) }
            .map { Section(group: $0, commands: grouped[$0] ?? []) }
    }

    /// Recents list after running `id`: most recent first, without duplicates.
    public static func recording(_ id: String, in recent: [String], keep: Int = 20) -> [String] {
        Array(([id] + recent.filter { $0 != id }).prefix(keep))
    }
}
