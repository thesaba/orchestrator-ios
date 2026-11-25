import Foundation

// Multi-server management, DigitalOcean droplet control, and root-level system operations.
// Everything here acts on the machine that hosts every site — the UI gates all of it
// behind explicit confirmations.

extension OrchestratorAPI {

    // MARK: - Managed servers

    public func servers() async throws -> [ManagedServer] {
        try await client.get("/servers", as: ServersResponse.self).servers
    }

    public func serverHealth(id: Int) async throws -> ServerHealth {
        try await client.get("/servers/\(id)/health")
    }

    @discardableResult
    public func createServer(_ draft: ServerDraft) async throws -> Data {
        try await client.send(.post, "/servers", body: draft)
    }

    @discardableResult
    public func updateServer(id: Int, _ draft: ServerDraft) async throws -> Data {
        try await client.send(.patch, "/servers/\(id)", body: draft)
    }

    @discardableResult
    public func deleteServer(id: Int) async throws -> Data {
        try await client.send(.delete, "/servers/\(id)")
    }

    @discardableResult
    public func testServer(id: Int) async throws -> Data {
        try await client.send(.post, "/servers/\(id)/test")
    }

    @discardableResult
    public func testServerConnection(_ draft: ServerDraft) async throws -> Data {
        try await client.send(.post, "/servers/test-connection", body: draft)
    }

    @discardableResult
    public func prepareServer(id: Int) async throws -> Data {
        try await client.send(.post, "/servers/\(id)/prepare")
    }

    public func serverPrepareStream(id: Int) -> AsyncThrowingStream<SSEEvent, Error> {
        client.events("/servers/\(id)/prepare/stream")
    }

    // MARK: - DigitalOcean droplet

    public func dropletStatus() async throws -> DropletStatus {
        try await client.get("/server/status")
    }

    public func droplets() async throws -> [Droplet] {
        try await client.get("/server/droplets")
    }

    public func dropletSizes() async throws -> [DropletSize] {
        try await client.get("/server/sizes")
    }

    public func dropletActions() async throws -> [DropletAction] {
        try await client.get("/server/actions")
    }

    public enum DropletActionType: String, CaseIterable, Identifiable, Sendable {
        case powerOn = "power_on"
        case powerOff = "power_off"
        case reboot
        case powerCycle = "power_cycle"
        case shutdown
        case enableBackups = "enable_backups"
        case disableBackups = "disable_backups"

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .powerOn:        return "Power on"
            case .powerOff:       return "Power off (hard)"
            case .reboot:         return "Reboot"
            case .powerCycle:     return "Power cycle"
            case .shutdown:       return "Shutdown (graceful)"
            case .enableBackups:  return "Enable backups"
            case .disableBackups: return "Disable backups"
            }
        }

        public var isDestructive: Bool {
            switch self {
            case .powerOff, .powerCycle, .reboot, .shutdown, .disableBackups: return true
            default: return false
            }
        }

        public var warning: String {
            switch self {
            case .powerOn:        return "Boots the droplet."
            case .powerOff:       return "Cuts power immediately, like pulling the plug. Every site goes offline and unwritten data can be lost."
            case .shutdown:       return "Asks the OS to shut down cleanly. Every site goes offline until you power it back on."
            case .reboot:         return "Every site is offline for the length of the reboot."
            case .powerCycle:     return "Hard power off followed by power on. Every site goes offline and unwritten data can be lost."
            case .enableBackups:  return "DigitalOcean starts charging for weekly backups."
            case .disableBackups: return "Existing backups are deleted by DigitalOcean."
            }
        }
    }

    public struct DropletActionRequest: Encodable, Sendable {
        public var type: String

        public init(type: String) {
            self.type = type
        }
    }

    @discardableResult
    public func performDropletAction(_ type: DropletActionType) async throws -> Data {
        try await client.send(.post, "/server/actions", body: DropletActionRequest(type: type.rawValue))
    }

    public struct ResizeRequest: Encodable, Sendable {
        public var size: String
        /// `true` grows the disk permanently and cannot be undone.
        public var disk: Bool

        public init(size: String, disk: Bool) {
            self.size = size
            self.disk = disk
        }
    }

    @discardableResult
    public func resizeDroplet(to size: String, resizeDisk: Bool) async throws -> Data {
        try await client.send(.post, "/server/resize", body: ResizeRequest(size: size, disk: resizeDisk))
    }

    public struct RenameRequest: Encodable, Sendable {
        public var name: String

        public init(name: String) {
            self.name = name
        }
    }

    @discardableResult
    public func renameDroplet(to name: String) async throws -> Data {
        try await client.send(.patch, "/server/rename", body: RenameRequest(name: name))
    }

    public func snapshots() async throws -> [DropletSnapshot] {
        try await client.get("/server/snapshots")
    }

    public func dropletBackups() async throws -> [DropletSnapshot] {
        try await client.get("/server/backups")
    }

    public struct SnapshotRequest: Encodable, Sendable {
        public var name: String

        public init(name: String) {
            self.name = name
        }
    }

    @discardableResult
    public func createSnapshot(named name: String) async throws -> Data {
        try await client.send(.post, "/server/snapshots", body: SnapshotRequest(name: name))
    }

    @discardableResult
    public func deleteSnapshot(id: Int) async throws -> Data {
        try await client.send(.delete, "/server/snapshots/\(id)")
    }

    public func firewalls() async throws -> [JSONValue] {
        try await client.get("/server/firewalls")
    }

    // MARK: - System operations

    /// `GET /api/system/run/:key/stream`, optionally with `?arg=`.
    public func systemOperationStream(_ operation: SystemOperation) -> AsyncThrowingStream<SSEEvent, Error> {
        client.events(
            "/system/run/\(operation.key)/stream",
            query: operation.argument.map { [URLQueryItem(name: "arg", value: $0)] } ?? []
        )
    }

    public struct ServiceControlRequest: Encodable, Sendable {
        public var action: String

        public init(action: String) {
            self.action = action
        }
    }

    public enum ServiceAction: String, CaseIterable, Identifiable, Sendable {
        case start, stop, restart, reload

        public var id: String { rawValue }
        public var title: String { rawValue.capitalized }
        public var isDestructive: Bool { self == .stop }
    }

    @discardableResult
    public func controlService(key: String, action: ServiceAction) async throws -> Data {
        try await client.send(
            .post,
            "/monitor/services/\(APIPath.segment(key))/control",
            body: ServiceControlRequest(action: action.rawValue)
        )
    }

    public func serviceLogs(key: String) async throws -> JSONValue {
        try await client.get("/monitor/services/\(APIPath.segment(key))/logs")
    }

    // MARK: - Uptime toggle

    public struct MonitoringRequest: Encodable, Sendable {
        public var monitoring: Bool

        public init(monitoring: Bool) {
            self.monitoring = monitoring
        }
    }

    @discardableResult
    public func setUptimeMonitoring(siteID: Int, enabled: Bool) async throws -> Data {
        try await client.send(.patch, "/uptime/\(siteID)", body: MonitoringRequest(monitoring: enabled))
    }
}
