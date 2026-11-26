import Foundation

/// `GET /api/fleet/scripts` — saved shell scripts that can run on many servers.
public struct FleetScript: Decodable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var name: String
    public var description: String?
    public var body: String
    public var timeoutSecs: Int?
    public var aiAllowed: Bool

    public init(id: Int, name: String, description: String?, body: String, timeoutSecs: Int?, aiAllowed: Bool) {
        self.id = id
        self.name = name
        self.description = description
        self.body = body
        self.timeoutSecs = timeoutSecs
        self.aiAllowed = aiAllowed
    }
}

struct FleetScriptsResponse: Decodable, Sendable { var scripts: [FleetScript] }

/// What a run executes: a saved script or a one-off command.
public enum FleetRunTask: Sendable, Hashable {
    case script(FleetScript)
    case command(String, timeoutSeconds: Int)

    public static let maxCommandLength = 20_000
    public static let maxTargets = 50
    public static let maxTimeout = 3600

    public var title: String {
        switch self {
        case .script(let script):     return script.name
        case .command(let text, _):   return text.split(separator: "\n").first.map(String.init) ?? text
        }
    }

    /// The shell text that will run on every server.
    public var shellText: String {
        switch self {
        case .script(let script):    return script.body
        case .command(let text, _):  return text
        }
    }

    /// Why the panel would refuse this run, or nil.
    public func problem(serverCount: Int) -> String? {
        if serverCount == 0 { return "Choose at least one server." }
        if serverCount > Self.maxTargets { return "At most \(Self.maxTargets) servers per run." }
        if case .command(let text, let timeout) = self {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return "Type a command." }
            if text.count > Self.maxCommandLength { return "The command is longer than \(Self.maxCommandLength) characters." }
            if !(1...Self.maxTimeout).contains(timeout) { return "The timeout must be between 1 second and 1 hour." }
        }
        return nil
    }
}

private struct FleetRunBody: Encodable, Sendable {
    var kind: String
    var serverIds: [Int]
    var command: String?
    var timeoutSec: Int?
    var scriptId: Int?
}

private struct FleetRunStarted: Decodable, Sendable { var runId: Int }

extension OrchestratorAPI {
    public func fleetScripts() async throws -> [FleetScript] {
        try await client.get("/fleet/scripts", as: FleetScriptsResponse.self).scripts
    }

    /// `POST /api/fleet/runs` — needs a password session stepped up with 2FA, and the
    /// "free commands" switch on each server. - Returns: the run id.
    public func startFleetRun(_ task: FleetRunTask, serverIDs: [Int]) async throws -> Int {
        let body: FleetRunBody
        switch task {
        case .script(let script):
            body = FleetRunBody(kind: "script", serverIds: serverIDs, command: nil, timeoutSec: nil, scriptId: script.id)
        case .command(let text, let timeout):
            body = FleetRunBody(kind: "command", serverIds: serverIDs, command: text, timeoutSec: timeout, scriptId: nil)
        }
        return try await client.post("/fleet/runs", body: body, as: FleetRunStarted.self).runId
    }

    @discardableResult
    public func cancelFleetRun(id: Int) async throws -> Data {
        try await client.send(.post, "/fleet/runs/\(id)/cancel", body: EmptyBody())
    }
}
