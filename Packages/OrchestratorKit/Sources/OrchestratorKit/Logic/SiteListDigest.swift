import Foundation

/// The site list with every embedded deploy log parsed once and then dropped.
///
/// `GET /sites` carries each site's newest deploy log (up to ~170 KB each). Keeping the logs
/// and re-parsing them on every refresh cost memory and main-thread time; the digest keeps
/// only the parsed summaries. Build it off the main actor.
public struct SiteListDigest: Sendable {
    public var sites: [SiteListing]
    /// Site id → summary of its newest deployment's log.
    public var summaries: [Int: DeployLogSummary]

    public init(_ listings: [SiteListing]) {
        var stripped = listings
        var summaries: [Int: DeployLogSummary] = [:]
        for index in stripped.indices {
            guard var deployment = stripped[index].deployments.first else { continue }
            if let log = deployment.log {
                summaries[stripped[index].id] = DeployLogParser.parse(log, status: deployment.status)
                deployment.log = nil
                stripped[index].deployments[0] = deployment
            }
        }
        self.sites = stripped
        self.summaries = summaries
    }
}
