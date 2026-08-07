import Foundation

/// `GET /api/servers`
struct ServersResponse: Decodable, Sendable {
    var servers: [ManagedServer]
}

struct ManagedServer: Decodable, Sendable, Hashable, Identifiable {
    var id: Int
    var name: String
    var kind: String?
    var host: String?
    var port: Int?
    var sshUser: String?
    var hasKey: Bool
    var sshKeyFingerprint: String?
    var status: String?
    var lastSeenAt: Date?
    var scriptsSynced: Bool
    var notes: String?
    var createdAt: Date?
    var siteCount: Int?

    var tone: StatusTone { StatusTone(status: status) }
    var address: String { "\(sshUser ?? "root")@\(host ?? "—"):\(port ?? 22)" }
    var isLocal: Bool { (kind ?? "").lowercased() == "local" }
}

/// `GET /api/servers/:id/health` — shape unconfirmed, read defensively.
struct ServerHealth: Decodable, Sendable {
    var ok: Bool?
    var message: String?
    var raw: JSONValue

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(JSONValue.self)
        raw = value
        ok = (value["ok"] ?? value["healthy"] ?? value["reachable"])?.boolValue
        message = (value["message"] ?? value["error"] ?? value["status"])?.stringValue
    }
}

struct ServerDraft: Encodable, Sendable {
    var name: String
    var host: String
    var port: Int
    var sshUser: String
    var privateKey: String?
    var notes: String?
}

// MARK: - DigitalOcean

/// `GET /api/server/status`
struct DropletStatus: Decodable, Sendable {
    var configured: Bool
    var droplet: Droplet?
    var needsDropletSelection: Bool
}

struct Droplet: Decodable, Sendable, Hashable, Identifiable {
    struct Size: Decodable, Sendable, Hashable {
        var slug: String?
        var memory: Int?
        var vcpus: Int?
        var disk: Int?
        var priceMonthly: Double?
        var available: Bool?
        var description: String?

        private enum CodingKeys: String, CodingKey {
            case slug, memory, vcpus, disk, available, description
            case priceMonthly = "price_monthly"
        }
    }

    struct Region: Decodable, Sendable, Hashable {
        var name: String?
        var slug: String?
    }

    struct Networks: Decodable, Sendable, Hashable {
        struct Address: Decodable, Sendable, Hashable {
            var ipAddress: String?
            var type: String?

            private enum CodingKeys: String, CodingKey {
                case type
                case ipAddress = "ip_address"
            }
        }
        var v4: [Address]?
        var v6: [Address]?
    }

    struct Image: Decodable, Sendable, Hashable {
        var distribution: String?
        var name: String?
    }

    var id: Int
    var name: String
    var memory: Int?
    var vcpus: Int?
    var disk: Int?
    var locked: Bool
    var status: String
    var createdAt: Date?
    var image: Image?
    var size: Size?
    var sizeSlug: String?
    var networks: Networks?
    var region: Region?

    private enum CodingKeys: String, CodingKey {
        case id, name, memory, vcpus, disk, locked, status, image, size, networks, region
        case createdAt = "created_at"
        case sizeSlug = "size_slug"
    }

    var tone: StatusTone {
        switch status.lowercased() {
        case "active":  return .good
        case "off":     return .critical
        case "new":     return .info
        default:        return .warning
        }
    }

    var publicIPv4: String? {
        networks?.v4?.first { ($0.type ?? "") == "public" }?.ipAddress
            ?? networks?.v4?.first?.ipAddress
    }

    var specs: String {
        let ram = memory.map { "\($0 / 1024) GB RAM" } ?? "—"
        let cpu = vcpus.map { "\($0) vCPU" } ?? "—"
        let ssd = disk.map { "\($0) GB" } ?? "—"
        return "\(cpu) · \(ram) · \(ssd)"
    }
}

/// `GET /api/server/sizes`
struct DropletSize: Decodable, Sendable, Hashable, Identifiable {
    var slug: String
    var memory: Int?
    var vcpus: Int?
    var disk: Int?
    var priceMonthly: Double?
    var available: Bool
    var description: String?

    private enum CodingKeys: String, CodingKey {
        case slug, memory, vcpus, disk, available, description
        case priceMonthly = "price_monthly"
    }

    var id: String { slug }

    var summary: String {
        let ram = memory.map { "\($0 / 1024) GB" } ?? "—"
        return "\(vcpus ?? 0) vCPU · \(ram) · \(disk ?? 0) GB SSD"
    }

    var priceLabel: String {
        priceMonthly.map { String(format: "$%.0f/mo", $0) } ?? "—"
    }
}

/// `GET /api/server/actions`
struct DropletAction: Decodable, Sendable, Hashable, Identifiable {
    var id: Int
    var status: String
    var type: String
    var startedAt: Date?
    var completedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id, status, type
        case startedAt = "started_at"
        case completedAt = "completed_at"
    }

    var tone: StatusTone {
        switch status.lowercased() {
        case "completed":   return .good
        case "in-progress": return .info
        case "errored":     return .critical
        default:            return .neutral
        }
    }
}

/// `GET /api/server/snapshots` and `/backups`
struct DropletSnapshot: Decodable, Sendable, Hashable, Identifiable {
    var id: Int
    var name: String
    var distribution: String?
    var createdAt: Date?
    var minDiskSize: Int?
    var type: String?
    var sizeGigabytes: Double?

    private enum CodingKeys: String, CodingKey {
        case id, name, distribution, type
        case createdAt = "created_at"
        case minDiskSize = "min_disk_size"
        case sizeGigabytes = "size_gigabytes"
    }

    var sizeLabel: String {
        sizeGigabytes.map { String(format: "%.2f GB", $0) } ?? "—"
    }
}

/// One entry in the system-control panel. Keys match `GET /api/system/run/:key/stream`.
struct SystemOperation: Identifiable, Hashable, Sendable {
    var key: String
    var title: String
    var subtitle: String
    var group: String
    /// Non-nil when the action needs a typed confirmation before it runs.
    var confirmation: String?
    var argument: String?

    var id: String { argument.map { "\(key)-\($0)" } ?? key }

    /// The catalogue the panel itself offers. Anything not listed here is not exposed,
    /// on purpose — these run as root on the machine hosting every site.
    static let catalogue: [SystemOperation] = [
        SystemOperation(key: "apt-update", title: "Check for updates",
                        subtitle: "apt-get update", group: "Packages", confirmation: nil, argument: nil),
        SystemOperation(key: "apt-upgrade", title: "Upgrade packages",
                        subtitle: "apt-get upgrade -y", group: "Packages",
                        confirmation: "Install all available package upgrades now? This can take several minutes and may restart services.",
                        argument: nil),
        SystemOperation(key: "apt-dist-upgrade", title: "Full upgrade",
                        subtitle: "apt-get dist-upgrade", group: "Packages",
                        confirmation: "A dist-upgrade may add or remove packages and change the kernel. A reboot is usually required afterwards.",
                        argument: nil),
        SystemOperation(key: "apt-autoremove", title: "Autoremove",
                        subtitle: "apt-get autoremove --purge", group: "Cleanup",
                        confirmation: "Remove packages that were installed as dependencies and are no longer needed?",
                        argument: nil),
        SystemOperation(key: "apt-clean", title: "Clean apt cache",
                        subtitle: "apt-get clean", group: "Cleanup", confirmation: nil, argument: nil),
        SystemOperation(key: "journal-vacuum", title: "Vacuum logs",
                        subtitle: "journalctl --vacuum-time=7d", group: "Cleanup", confirmation: nil, argument: nil),
        SystemOperation(key: "ufw-status", title: "Firewall status",
                        subtitle: "ufw status", group: "Firewall", confirmation: nil, argument: nil),
        SystemOperation(key: "ufw-enable", title: "Enable firewall",
                        subtitle: "ufw enable", group: "Firewall",
                        confirmation: "Enable the firewall now? Make sure SSH (port 22) is allowed first, or you will lock yourself out of the server.",
                        argument: nil)
    ]

    static func ufwAllow(_ rule: String) -> SystemOperation {
        SystemOperation(key: "ufw-allow", title: "Allow \(rule)", subtitle: "ufw allow \(rule)",
                        group: "Firewall", confirmation: nil, argument: rule)
    }

    static func ufwDeny(_ rule: String) -> SystemOperation {
        SystemOperation(key: "ufw-deny", title: "Deny \(rule)", subtitle: "ufw deny \(rule)",
                        group: "Firewall", confirmation: "Deny all traffic on \(rule)?", argument: rule)
    }

    /// The panel only accepts a port number or one of these service names.
    static func isValidRule(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespaces).lowercased()
        if ["ssh", "http", "https", "ftp", "smtp"].contains(value) { return true }
        guard let port = Int(value) else { return false }
        return (1...65535).contains(port)
    }
}
