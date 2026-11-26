import Foundation

// One fleet server in depth: processes, inventory (services, updates, containers), disk
// forecast, and the fixed actions the panel can run on it. Shapes follow
// `apps/api/src/lib/fleet/contract.ts` and `routes/fleet.ts` of the panel.

/// `GET /api/fleet/servers/:id/processes?sort=cpu|mem&limit=`
public struct FleetProcesses: Decodable, Sendable, Hashable {
    public struct Process: Decodable, Sendable, Hashable, Identifiable {
        public var pid: Int
        public var user: String?
        public var name: String
        public var cmd: String?
        /// Percent of one core summed over cores, as `ps` reports it.
        public var cpu: Double
        /// Percent of RAM.
        public var mem: Double
        public var rss: Int?

        public var id: Int { pid }
    }

    public var processes: [Process]
    public var channel: String?
}

/// `GET /api/fleet/servers/:id/inventory` — `inventory` is null until the server reported one.
public struct FleetInventoryResponse: Decodable, Sendable, Hashable {
    public var inventory: FleetInventory?
    public var at: Date?
    public var channel: String?
}

public struct FleetInventory: Decodable, Sendable, Hashable {
    public struct Service: Decodable, Sendable, Hashable, Identifiable {
        public var name: String
        public var description: String?
        /// `active`, `inactive`, `failed`.
        public var active: String
        /// `running`, `exited`, `dead`.
        public var sub: String?
        public var enabled: String?

        public var id: String { name }
        public var isFailed: Bool { active == "failed" }
        public var isRunning: Bool { active == "active" }
    }

    public struct Container: Decodable, Sendable, Hashable, Identifiable {
        public var id: String
        public var name: String
        public var image: String?
        public var state: String
        public var status: String?
        public var cpu: Double?
        public var memBytes: Int?
    }

    public struct Docker: Decodable, Sendable, Hashable {
        public var available: Bool
        public var containers: [Container]
    }

    public struct Package: Decodable, Sendable, Hashable, Identifiable {
        public var name: String
        public var current: String?
        public var available: String?
        public var security: Bool

        public var id: String { name }
    }

    public struct Updates: Decodable, Sendable, Hashable {
        public var manager: String?
        public var count: Int
        public var security: Int
        public var rebootRequired: Bool
        public var packages: [Package]
    }

    public var services: [Service]
    public var failedUnits: [String]
    public var docker: Docker?
    public var updates: Updates?
    public var os: String?
    public var kernel: String?
    public var hostname: String?
    public var timezone: String?
}

/// `GET /api/fleet/servers/:id/forecast`
public struct FleetForecast: Decodable, Sendable, Hashable {
    public struct Mount: Decodable, Sendable, Hashable, Identifiable {
        public var mount: String
        public var usedPct: Double
        /// Days until full at the recent rate; only for `/`, nil when not growing.
        public var daysLeft: Double?

        public var id: String { mount }
    }

    public var mounts: [Mount]
}

/// `GET /api/fleet/runs/:id` — an action or script and its result per server.
public struct FleetRun: Decodable, Sendable, Hashable, Identifiable {
    public struct Target: Decodable, Sendable, Hashable, Identifiable {
        public var id: Int
        public var serverId: Int
        public var serverName: String?
        /// `pending`, `running`, `success`, `failed`, `offline`, `cancelled`.
        public var status: String
        public var exitCode: Int?
        public var output: String?

        public var isFinished: Bool { !["pending", "running"].contains(status) }
    }

    public var id: Int
    public var command: String
    public var finishedAt: Date?
    public var targets: [Target]

    public var isFinished: Bool { finishedAt != nil || (!targets.isEmpty && targets.allSatisfy(\.isFinished)) }
}

/// The fixed actions `POST /api/fleet/servers/:id/actions` accepts. Nothing else can run
/// through it: no free commands.
public enum FleetAction: Sendable, Hashable {
    case service(ServiceVerb, name: String)
    case reboot(delayMinutes: Int)
    case cancelReboot
    case updatePackages(distUpgrade: Bool)
    case container(ContainerVerb, id: String, name: String)

    public enum ServiceVerb: String, Sendable, CaseIterable { case start, stop, restart, reload }
    public enum ContainerVerb: String, Sendable, CaseIterable { case start, stop, restart }

    /// The `action` field.
    public var apiName: String {
        switch self {
        case .service(let verb, _):   return "service.\(verb.rawValue)"
        case .reboot:                 return "reboot"
        case .cancelReboot:           return "reboot.cancel"
        case .updatePackages:         return "packages.update"
        case .container(let verb, _, _): return "docker.\(verb.rawValue)"
        }
    }

    /// The `args` object.
    public var args: [String: JSONValue] {
        switch self {
        case .service(_, let name):        return ["name": .string(name)]
        case .reboot(let delay):           return delay > 0 ? ["delayMin": .number(Double(delay))] : [:]
        case .cancelReboot:                return [:]
        case .updatePackages(let dist):    return ["mode": .string(dist ? "dist-upgrade" : "upgrade")]
        case .container(_, let id, _):     return ["id": .string(id)]
        }
    }

    /// Takes something offline or can break it: confirmed with Touch ID.
    public var isDestructive: Bool {
        switch self {
        case .service(let verb, _):      return verb == .stop
        case .reboot:                    return true
        case .cancelReboot:              return false
        case .updatePackages:            return true
        case .container(let verb, _, _): return verb == .stop
        }
    }

    /// "Restart nginx", "Reboot", "Stop container n8n".
    public var title: String {
        switch self {
        case .service(let verb, let name):     return "\(verb.rawValue.capitalized) \(name)"
        case .reboot(let delay):               return delay > 0 ? "Reboot in \(delay) min" : "Reboot"
        case .cancelReboot:                    return "Cancel the scheduled reboot"
        case .updatePackages(let dist):        return dist ? "Upgrade all packages (dist-upgrade)" : "Update packages"
        case .container(let verb, _, let name): return "\(verb.rawValue.capitalized) container \(name)"
        }
    }
}

extension OrchestratorAPI {
    public func fleetProcesses(serverID: Int, sortByMemory: Bool = false, limit: Int = 30) async throws -> FleetProcesses {
        try await client.get("/fleet/servers/\(serverID)/processes",
                             query: [URLQueryItem(name: "sort", value: sortByMemory ? "mem" : "cpu"),
                                     URLQueryItem(name: "limit", value: String(limit))])
    }

    /// The newest inventory the panel has; it asks the server only when that is stale.
    public func fleetInventory(serverID: Int) async throws -> FleetInventoryResponse {
        try await client.get("/fleet/servers/\(serverID)/inventory")
    }

    public func fleetForecast(serverID: Int) async throws -> FleetForecast {
        try await client.get("/fleet/servers/\(serverID)/forecast")
    }

    public func fleetRun(id: Int) async throws -> FleetRun {
        try await client.get("/fleet/runs/\(id)")
    }

    private struct FleetActionBody: Encodable, Sendable {
        var action: String
        var args: [String: JSONValue]?
    }

    private struct FleetRunStart: Decodable, Sendable { var runId: Int }

    /// Starts one fixed action; the result arrives on the run. - Returns: the run id.
    public func startFleetAction(serverID: Int, _ action: FleetAction) async throws -> Int {
        let args = action.args
        return try await client.post("/fleet/servers/\(serverID)/actions",
                                     body: FleetActionBody(action: action.apiName, args: args.isEmpty ? nil : args),
                                     as: FleetRunStart.self).runId
    }
}
