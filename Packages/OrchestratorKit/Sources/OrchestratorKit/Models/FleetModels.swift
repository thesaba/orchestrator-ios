import Foundation

/// `GET /api/fleet/servers` — admin only.
///
/// Shape: `FleetServerOut` in `apps/api/src/lib/fleet/serialize.ts` of the panel. Server ids
/// are the same ids as `GET /api/servers`, and a site whose `serverId` is null runs on the
/// server with `kind == "local"`.
public struct FleetServersResponse: Decodable, Sendable {
    public var servers: [FleetServer]
    public var shippedAgentVersion: String?
}

public struct FleetServer: Decodable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var name: String
    /// `local` (the panel host) or `remote`.
    public var kind: String
    public var host: String?
    public var hasSsh: Bool
    /// `none`, `pending`, `online` or `offline`.
    public var agentStatus: String
    public var agentVersion: String?
    public var agentMode: String?
    public var agentLastSeenAt: Date?
    public var agentUpdateAvailable: Bool
    /// The channel actions use right now: `agent`, `ssh`, `local` or `none`.
    public var channel: String
    public var location: String?
    public var groupName: String?
    public var tags: [String]
    public var provider: String?
    public var latencyMs: Double?
    public var maintenanceUntil: Date?
    public var siteCount: Int
    public var latest: FleetLatestMetrics?
    public var activeAlerts: Int
    /// The server's switch for the web terminal.
    public var terminalEnabled: Bool = false
    /// The server's switch for free commands and saved scripts run from a person's session.
    public var commandsEnabled: Bool = false

    public var isLocal: Bool { kind == "local" }

    /// CPU usage in percent, when metrics exist.
    public var cpuPercent: Double? { latest?.m.cpu.percent }

    /// RAM usage in percent, when metrics exist.
    public var ramPercent: Double? { latest?.m.mem.usedPercent }

    /// The root disk, or the fullest disk when there is no `/` mount.
    public var primaryDisk: FleetDisk? {
        guard let disks = latest?.m.disks, !disks.isEmpty else { return nil }
        return disks.first(where: { $0.mount == "/" }) ?? disks.max(by: { $0.usedPercent < $1.usedPercent })
    }

    public var diskPercent: Double? { primaryDisk?.usedPercent }

    public init(id: Int, name: String, kind: String = "remote", host: String? = nil, hasSsh: Bool = false,
                agentStatus: String = "none", agentVersion: String? = nil, agentMode: String? = nil,
                agentLastSeenAt: Date? = nil, agentUpdateAvailable: Bool = false, channel: String = "none",
                location: String? = nil, groupName: String? = nil, tags: [String] = [], provider: String? = nil,
                latencyMs: Double? = nil, maintenanceUntil: Date? = nil, siteCount: Int = 0,
                latest: FleetLatestMetrics? = nil, activeAlerts: Int = 0) {
        self.id = id
        self.name = name
        self.kind = kind
        self.host = host
        self.hasSsh = hasSsh
        self.agentStatus = agentStatus
        self.agentVersion = agentVersion
        self.agentMode = agentMode
        self.agentLastSeenAt = agentLastSeenAt
        self.agentUpdateAvailable = agentUpdateAvailable
        self.channel = channel
        self.location = location
        self.groupName = groupName
        self.tags = tags
        self.provider = provider
        self.latencyMs = latencyMs
        self.maintenanceUntil = maintenanceUntil
        self.siteCount = siteCount
        self.latest = latest
        self.activeAlerts = activeAlerts
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, host, hasSsh, agentStatus, agentVersion, agentMode, agentLastSeenAt
        case agentUpdateAvailable, channel, location, groupName, tags, provider, latencyMs
        case maintenanceUntil, siteCount, latest, activeAlerts, terminalEnabled, commandsEnabled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "remote"
        host = try c.decodeIfPresent(String.self, forKey: .host)
        hasSsh = try c.decode(Bool.self, forKey: .hasSsh)
        agentStatus = try c.decodeIfPresent(String.self, forKey: .agentStatus) ?? "none"
        agentVersion = try c.decodeIfPresent(String.self, forKey: .agentVersion)
        agentMode = try c.decodeIfPresent(String.self, forKey: .agentMode)
        agentLastSeenAt = try c.decodeIfPresent(Date.self, forKey: .agentLastSeenAt)
        agentUpdateAvailable = try c.decode(Bool.self, forKey: .agentUpdateAvailable)
        channel = try c.decodeIfPresent(String.self, forKey: .channel) ?? "none"
        location = try c.decodeIfPresent(String.self, forKey: .location)
        groupName = try c.decodeIfPresent(String.self, forKey: .groupName)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        provider = try c.decodeIfPresent(String.self, forKey: .provider)
        latencyMs = try c.decodeIfPresent(Double.self, forKey: .latencyMs)
        maintenanceUntil = try c.decodeIfPresent(Date.self, forKey: .maintenanceUntil)
        siteCount = try c.decodeIfPresent(Int.self, forKey: .siteCount) ?? 0
        latest = try c.decodeIfPresent(FleetLatestMetrics.self, forKey: .latest)
        activeAlerts = try c.decodeIfPresent(Int.self, forKey: .activeAlerts) ?? 0
        terminalEnabled = try c.decodeIfPresent(Bool.self, forKey: .terminalEnabled) ?? false
        commandsEnabled = try c.decodeIfPresent(Bool.self, forKey: .commandsEnabled) ?? false
    }
}

/// `latest` of a fleet server: the newest sample from the agent, SSH sampling or the panel host.
public struct FleetLatestMetrics: Decodable, Sendable, Hashable {
    public var at: Date
    /// `agent`, `ssh` or `local`.
    public var source: String
    public var m: FleetMetrics

    public init(at: Date, source: String, m: FleetMetrics) {
        self.at = at
        self.source = source
        self.m = m
    }
}

/// `FleetMetrics` of the panel's fleet contract. Byte counts are plain numbers.
public struct FleetMetrics: Decodable, Sendable, Hashable {
    public struct CPU: Decodable, Sendable, Hashable {
        public var percent: Double
        public var load1: Double?
        public var load5: Double?
        public var load15: Double?
        public var cores: Int?

        public init(percent: Double, load1: Double? = nil, load5: Double? = nil, load15: Double? = nil, cores: Int? = nil) {
            self.percent = percent
            self.load1 = load1
            self.load5 = load5
            self.load15 = load15
            self.cores = cores
        }
    }

    public struct Memory: Decodable, Sendable, Hashable {
        public var total: Double
        public var used: Double
        public var swapTotal: Double?
        public var swapUsed: Double?

        public var usedPercent: Double? { total > 0 ? used / total * 100 : nil }

        public init(total: Double, used: Double, swapTotal: Double? = nil, swapUsed: Double? = nil) {
            self.total = total
            self.used = used
            self.swapTotal = swapTotal
            self.swapUsed = swapUsed
        }
    }

    public struct Network: Decodable, Sendable, Hashable {
        public var rxBps: Double
        public var txBps: Double
    }

    public var cpu: CPU
    public var mem: Memory
    public var disks: [FleetDisk]
    public var net: Network?
    /// Seconds since boot.
    public var uptime: Double?

    public init(cpu: CPU, mem: Memory, disks: [FleetDisk] = [], net: Network? = nil, uptime: Double? = nil) {
        self.cpu = cpu
        self.mem = mem
        self.disks = disks
        self.net = net
        self.uptime = uptime
    }

    private enum CodingKeys: String, CodingKey { case cpu, mem, disks, net, uptime }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cpu = try c.decode(CPU.self, forKey: .cpu)
        mem = try c.decode(Memory.self, forKey: .mem)
        disks = try c.decodeIfPresent([FleetDisk].self, forKey: .disks) ?? []
        net = try c.decodeIfPresent(Network.self, forKey: .net)
        uptime = try c.decodeIfPresent(Double.self, forKey: .uptime)
    }
}

public struct FleetDisk: Decodable, Sendable, Hashable {
    public var mount: String
    public var total: Double
    public var used: Double

    public var usedPercent: Double { total > 0 ? used / total * 100 : 0 }

    public init(mount: String, total: Double, used: Double) {
        self.mount = mount
        self.total = total
        self.used = used
    }
}

/// `GET /api/fleet/alerts?active=1&limit=` — admin only.
public struct FleetAlertsResponse: Decodable, Sendable {
    public var events: [FleetAlertEvent]
}

public struct FleetAlertEvent: Decodable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var serverId: Int
    public var serverName: String
    /// `cpu`, `ram`, `disk`, `swap`, `load`, `inode`, `offline`, `disk_forecast`, `service_failed`.
    public var kind: String
    public var message: String?
    public var value: Double?
    public var startedAt: Date
    public var resolvedAt: Date?

    public var isActive: Bool { resolvedAt == nil }

    public init(id: Int, serverId: Int, serverName: String, kind: String, message: String? = nil,
                value: Double? = nil, startedAt: Date, resolvedAt: Date? = nil) {
        self.id = id
        self.serverId = serverId
        self.serverName = serverName
        self.kind = kind
        self.message = message
        self.value = value
        self.startedAt = startedAt
        self.resolvedAt = resolvedAt
    }
}
