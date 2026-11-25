import Foundation

/// One site with its mark, built from the uptime check and, when loaded, the site list.
public struct SiteStatus: Sendable, Hashable, Identifiable {
    public var id: Int
    public var name: String
    public var domain: String
    public var mark: HealthMark
    /// "Up", "Down", "Deploying", "Not monitored".
    public var label: String
    public var branch: String?
    public var shortCommit: String?
    /// When the newest deployment started.
    public var lastDeployAt: Date?
    public var lastDeployStatus: String?
    /// Parsed from the newest deployment's log, when the site list is loaded.
    public var deploy: DeployLogSummary?

    public var isDeploying: Bool { mark == .deploying }

    public init(id: Int, name: String, domain: String, mark: HealthMark, label: String,
                branch: String? = nil, shortCommit: String? = nil, lastDeployAt: Date? = nil,
                lastDeployStatus: String? = nil, deploy: DeployLogSummary? = nil) {
        self.id = id
        self.name = name
        self.domain = domain
        self.mark = mark
        self.label = label
        self.branch = branch
        self.shortCommit = shortCommit
        self.lastDeployAt = lastDeployAt
        self.lastDeployStatus = lastDeployStatus
        self.deploy = deploy
    }
}
