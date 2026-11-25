import Foundation

/// `GET /api/servers`
public struct ServersResponse: Decodable, Sendable {
    public var servers: [ManagedServer]
}

public struct ManagedServer: Decodable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var name: String
    public var kind: String?
    public var host: String?
    public var port: Int?
    public var sshUser: String?
    public var hasKey: Bool
    public var sshKeyFingerprint: String?
    public var status: String?
    public var lastSeenAt: Date?
    public var scriptsSynced: Bool
    public var notes: String?
    public var createdAt: Date?
    public var siteCount: Int?

    public var tone: StatusTone { StatusTone(status: status) }
    public var address: String { "\(sshUser ?? "root")@\(host ?? "—"):\(port ?? 22)" }
    public var isLocal: Bool { (kind ?? "").lowercased() == "local" }
}

/// `GET /api/servers/:id/health` — shape unconfirmed, read defensively.
public struct ServerHealth: Decodable, Sendable {
    public var ok: Bool?
    public var message: String?
    public var raw: JSONValue

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(JSONValue.self)
        raw = value
        ok = (value["ok"] ?? value["healthy"] ?? value["reachable"])?.boolValue
        message = (value["message"] ?? value["error"] ?? value["status"])?.stringValue
    }
}

public struct ServerDraft: Encodable, Sendable {
    public var name: String
    public var host: String
    public var port: Int
    public var sshUser: String
    public var privateKey: String?
    public var notes: String?

    public init(name: String, host: String, port: Int, sshUser: String, privateKey: String? = nil, notes: String? = nil) {
        self.name = name
        self.host = host
        self.port = port
        self.sshUser = sshUser
        self.privateKey = privateKey
        self.notes = notes
    }
}

// MARK: - DigitalOcean

/// `GET /api/server/status`
public struct DropletStatus: Decodable, Sendable {
    public var configured: Bool
    public var droplet: Droplet?
    public var needsDropletSelection: Bool
}

public struct Droplet: Decodable, Sendable, Hashable, Identifiable {
    public struct Size: Decodable, Sendable, Hashable {
        public var slug: String?
        public var memory: Int?
        public var vcpus: Int?
        public var disk: Int?
        public var priceMonthly: Double?
        public var available: Bool?
        public var description: String?

        private enum CodingKeys: String, CodingKey {
            case slug, memory, vcpus, disk, available, description
            case priceMonthly = "price_monthly"
        }
    }

    public struct Region: Decodable, Sendable, Hashable {
        public var name: String?
        public var slug: String?
    }

    public struct Networks: Decodable, Sendable, Hashable {
        public struct Address: Decodable, Sendable, Hashable {
            public var ipAddress: String?
            public var type: String?

            private enum CodingKeys: String, CodingKey {
                case type
                case ipAddress = "ip_address"
            }
        }
        public var v4: [Address]?
        public var v6: [Address]?
    }

    public struct Image: Decodable, Sendable, Hashable {
        public var distribution: String?
        public var name: String?
    }

    public var id: Int
    public var name: String
    public var memory: Int?
    public var vcpus: Int?
    public var disk: Int?
    public var locked: Bool
    public var status: String
    public var createdAt: Date?
    public var image: Image?
    public var size: Size?
    public var sizeSlug: String?
    public var networks: Networks?
    public var region: Region?

    private enum CodingKeys: String, CodingKey {
        case id, name, memory, vcpus, disk, locked, status, image, size, networks, region
        case createdAt = "created_at"
        case sizeSlug = "size_slug"
    }

    public var tone: StatusTone {
        switch status.lowercased() {
        case "active":  return .good
        case "off":     return .critical
        case "new":     return .info
        default:        return .warning
        }
    }

    public var publicIPv4: String? {
        networks?.v4?.first { ($0.type ?? "") == "public" }?.ipAddress
            ?? networks?.v4?.first?.ipAddress
    }

    public var specs: String {
        let ram = memory.map { "\($0 / 1024) GB RAM" } ?? "—"
        let cpu = vcpus.map { "\($0) vCPU" } ?? "—"
        let ssd = disk.map { "\($0) GB" } ?? "—"
        return "\(cpu) · \(ram) · \(ssd)"
    }
}

/// `GET /api/server/sizes`
public struct DropletSize: Decodable, Sendable, Hashable, Identifiable {
    public var slug: String
    public var memory: Int?
    public var vcpus: Int?
    public var disk: Int?
    public var priceMonthly: Double?
    public var available: Bool
    public var description: String?

    private enum CodingKeys: String, CodingKey {
        case slug, memory, vcpus, disk, available, description
        case priceMonthly = "price_monthly"
    }

    public var id: String { slug }

    public var summary: String {
        let ram = memory.map { "\($0 / 1024) GB" } ?? "—"
        return "\(vcpus ?? 0) vCPU · \(ram) · \(disk ?? 0) GB SSD"
    }

    public var priceLabel: String {
        priceMonthly.map { String(format: "$%.0f/mo", $0) } ?? "—"
    }
}

/// `GET /api/server/actions`
public struct DropletAction: Decodable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var status: String
    public var type: String
    public var startedAt: Date?
    public var completedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id, status, type
        case startedAt = "started_at"
        case completedAt = "completed_at"
    }

    public var tone: StatusTone {
        switch status.lowercased() {
        case "completed":   return .good
        case "in-progress": return .info
        case "errored":     return .critical
        default:            return .neutral
        }
    }
}

/// `GET /api/server/snapshots` and `/backups`
public struct DropletSnapshot: Decodable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var name: String
    public var distribution: String?
    public var createdAt: Date?
    public var minDiskSize: Int?
    public var type: String?
    public var sizeGigabytes: Double?

    private enum CodingKeys: String, CodingKey {
        case id, name, distribution, type
        case createdAt = "created_at"
        case minDiskSize = "min_disk_size"
        case sizeGigabytes = "size_gigabytes"
    }

    public var sizeLabel: String {
        sizeGigabytes.map { String(format: "%.2f GB", $0) } ?? "—"
    }
}

/// One entry in the system-control panel. Keys match `GET /api/system/run/:key/stream`.
public struct SystemOperation: Identifiable, Hashable, Sendable {
    public var key: String
    public var title: String
    public var subtitle: String
    public var group: String
    /// Non-nil when the action needs a typed confirmation before it runs.
    public var confirmation: String?
    public var argument: String?

    public var id: String { argument.map { "\(key)-\($0)" } ?? key }

    /// The catalogue the panel itself offers. Anything not listed here is not exposed,
    /// on purpose — these run as root on the machine hosting every site.
    public static let catalogue: [SystemOperation] = [
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

    public static func ufwAllow(_ rule: String) -> SystemOperation {
        SystemOperation(key: "ufw-allow", title: "Allow \(rule)", subtitle: "ufw allow \(rule)",
                        group: "Firewall", confirmation: nil, argument: rule)
    }

    public static func ufwDeny(_ rule: String) -> SystemOperation {
        SystemOperation(key: "ufw-deny", title: "Deny \(rule)", subtitle: "ufw deny \(rule)",
                        group: "Firewall", confirmation: "Deny all traffic on \(rule)?", argument: rule)
    }

    /// The panel only accepts a port number or one of these service names.
    public static func isValidRule(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespaces).lowercased()
        if ["ssh", "http", "https", "ftp", "smtp"].contains(value) { return true }
        guard let port = Int(value) else { return false }
        return (1...65535).contains(port)
    }
}
