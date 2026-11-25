import Foundation

/// `GET /api/monitor/system`
public struct SystemSnapshot: Decodable, Sendable, Hashable {
    public struct CPU: Decodable, Sendable, Hashable {
        public var load1: Double?
        public var load5: Double?
        public var load15: Double?
        public var cores: Int?
        public var percent: Int?
    }

    public struct Memory: Decodable, Sendable, Hashable {
        public var total: Int?
        public var used: Int?
        public var free: Int?
        public var percent: Int?
    }

    public struct Storage: Decodable, Sendable, Hashable {
        public var total: Int?
        public var used: Int?
        public var percent: Int?
    }

    public var cpu: CPU
    public var ram: Memory
    public var disk: Storage
    public var swap: Memory?
    public var uptime: Int?
    public var hostname: String?
}
