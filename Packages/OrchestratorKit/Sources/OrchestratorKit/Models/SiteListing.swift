import Foundation

/// One row of `GET /api/sites`, as the Mac app reads it.
///
/// The list embeds exactly one deployment per site (the newest) *with* its full log; the
/// panel flushes that log to the database every few seconds while a deploy runs. Unlike
/// `Site`/`Deployment`, this keeps the log so the current step and commit message can be
/// read without attaching to the deploy stream. Callers should parse and drop it.
public struct SiteListing: Decodable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var name: String
    public var domain: String
    public var serverId: Int?
    public var status: String
    public var branch: String?
    public var disabled: Bool
    public var maintenanceMode: Bool
    public var deployQueued: Bool
    public var sslEnabled: Bool
    public var sslDaysLeft: Int?
    public var billingSuspended: Bool
    public var phpVersion: String?
    /// Set when this site is a staging copy of the site with this id.
    public var stagingOf: Int?
    public var deployments: [DeploymentRecord]

    public var latestDeployment: DeploymentRecord? { deployments.first }
    public var isDeploying: Bool { latestDeployment?.isRunning ?? false }
    public var isStaging: Bool { stagingOf != nil }

    public init(id: Int, name: String, domain: String, serverId: Int? = nil, status: String = "active",
                branch: String? = nil, disabled: Bool = false, maintenanceMode: Bool = false,
                deployQueued: Bool = false, sslEnabled: Bool = false, sslDaysLeft: Int? = nil,
                billingSuspended: Bool = false, phpVersion: String? = nil, stagingOf: Int? = nil, deployments: [DeploymentRecord] = []) {
        self.id = id
        self.name = name
        self.domain = domain
        self.serverId = serverId
        self.status = status
        self.branch = branch
        self.disabled = disabled
        self.maintenanceMode = maintenanceMode
        self.deployQueued = deployQueued
        self.sslEnabled = sslEnabled
        self.sslDaysLeft = sslDaysLeft
        self.billingSuspended = billingSuspended
        self.phpVersion = phpVersion
        self.stagingOf = stagingOf
        self.deployments = deployments
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, domain, serverId, status, branch, disabled, maintenanceMode, deployQueued
        case sslEnabled, sslDaysLeft, billingSuspended, phpVersion, stagingOf, deployments
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        domain = try c.decode(String.self, forKey: .domain)
        serverId = try c.decodeIfPresent(Int.self, forKey: .serverId)
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "active"
        branch = try c.decodeIfPresent(String.self, forKey: .branch)
        disabled = try c.decode(Bool.self, forKey: .disabled)
        maintenanceMode = try c.decode(Bool.self, forKey: .maintenanceMode)
        deployQueued = try c.decode(Bool.self, forKey: .deployQueued)
        sslEnabled = try c.decode(Bool.self, forKey: .sslEnabled)
        sslDaysLeft = try c.decodeIfPresent(Int.self, forKey: .sslDaysLeft)
        billingSuspended = try c.decode(Bool.self, forKey: .billingSuspended)
        phpVersion = try c.decodeIfPresent(String.self, forKey: .phpVersion)
        stagingOf = try c.decodeIfPresent(Int.self, forKey: .stagingOf)
        deployments = try c.decodeIfPresent([DeploymentRecord].self, forKey: .deployments) ?? []
    }
}

/// A deployment row including its log text.
public struct DeploymentRecord: Decodable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var siteId: Int
    public var commit: String?
    public var branch: String?
    /// `running`, `success`, `failed`, `cancelled`, …
    public var status: String
    public var log: String?
    public var testResult: String?
    public var createdAt: Date?

    public var isRunning: Bool { status == "running" }

    public var shortCommit: String? {
        guard let commit, !commit.isEmpty else { return nil }
        return String(commit.prefix(7))
    }

    public init(id: Int, siteId: Int, commit: String? = nil, branch: String? = nil, status: String,
                log: String? = nil, testResult: String? = nil, createdAt: Date? = nil) {
        self.id = id
        self.siteId = siteId
        self.commit = commit
        self.branch = branch
        self.status = status
        self.log = log
        self.testResult = testResult
        self.createdAt = createdAt
    }
}
