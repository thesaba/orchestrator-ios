import Foundation

/// `GET /api/monitor/system`
struct SystemSnapshot: Decodable, Sendable, Hashable {
    struct CPU: Decodable, Sendable, Hashable {
        var load1: Double?
        var load5: Double?
        var load15: Double?
        var cores: Int?
        var percent: Int?
    }

    struct Memory: Decodable, Sendable, Hashable {
        var total: Int?
        var used: Int?
        var free: Int?
        var percent: Int?
    }

    struct Storage: Decodable, Sendable, Hashable {
        var total: Int?
        var used: Int?
        var percent: Int?
    }

    var cpu: CPU
    var ram: Memory
    var disk: Storage
    var swap: Memory?
    var uptime: Int?
    var hostname: String?
}
