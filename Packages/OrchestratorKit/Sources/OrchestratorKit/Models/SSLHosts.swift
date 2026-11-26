import Foundation

/// `GET /api/sites/:id/ssl/hosts` — every host name of the site: the primary domain, the
/// names in its nginx vhost and those only on the certificate.
public struct SSLHosts: Decodable, Sendable, Hashable {
    public struct Host: Decodable, Sendable, Hashable, Identifiable {
        public var host: String
        public var primary: Bool
        /// Has a server block in nginx.
        public var inNginx: Bool
        /// That block listens on 443.
        public var https: Bool
        /// The certificate in the vhost, when one is configured.
        public var cert: String?
        /// The live certificate lists this name.
        public var covered: Bool
        /// The name resolves in DNS.
        public var dns: Bool

        public var id: String { host }

        private enum CodingKeys: String, CodingKey { case host, primary, inNginx, https, cert, covered, dns }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            host = try c.decode(String.self, forKey: .host)
            primary = try c.decodeIfPresent(Bool.self, forKey: .primary) ?? false
            inNginx = try c.decodeIfPresent(Bool.self, forKey: .inNginx) ?? false
            https = try c.decodeIfPresent(Bool.self, forKey: .https) ?? false
            // `cert` may come back as a name or as an object; only a name is kept.
            cert = try? c.decodeIfPresent(String.self, forKey: .cert)
            covered = try c.decodeIfPresent(Bool.self, forKey: .covered) ?? false
            dns = (try? c.decodeIfPresent(Bool.self, forKey: .dns)) ?? false
        }
    }

    public var certActive: Bool
    public var certName: String?
    public var running: Bool
    public var hosts: [Host]
}

extension OrchestratorAPI {
    /// The site's host names and whether the certificate covers each. Read-only.
    public func sslHosts(siteID: Int) async throws -> SSLHosts {
        try await client.get("/sites/\(siteID)/ssl/hosts")
    }
}
