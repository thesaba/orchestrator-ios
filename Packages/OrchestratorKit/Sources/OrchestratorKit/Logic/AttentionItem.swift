import Foundation

/// One row of "Needs attention": a server alert, an expiring certificate or a site that is down.
public struct AttentionItem: Sendable, Hashable, Identifiable {
    public enum Subject: Sendable, Hashable {
        case server(id: Int, alertID: Int, kind: String)
        case certificate(siteID: Int)
        case siteDown(siteID: Int)
    }

    public var id: String
    public var subject: Subject
    public var severity: HealthMark
    /// "Disk at 91%", "SSL expires in 6 days", "Site down".
    public var title: String
    /// Server name or domain.
    public var source: String
    /// When the condition started, if known.
    public var since: Date?
    /// Bucket for the "1 disk · 1 SSL" breakdown.
    public var category: String

    public init(id: String, subject: Subject, severity: HealthMark, title: String,
                source: String, since: Date? = nil, category: String) {
        self.id = id
        self.subject = subject
        self.severity = severity
        self.title = title
        self.source = source
        self.since = since
        self.category = category
    }
}
