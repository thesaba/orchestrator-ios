import AppIntents
import OrchestratorKit

/// A site, as Shortcuts and Spotlight see it. Comes from the app's site list (GET /sites).
struct SiteEntity: AppEntity, Identifiable, Sendable {
    let id: Int
    let domain: String
    let name: String

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Site"
    static let defaultQuery = SiteQuery()

    var displayRepresentation: DisplayRepresentation {
        name.caseInsensitiveCompare(domain) == .orderedSame
            ? DisplayRepresentation(title: "\(domain)")
            : DisplayRepresentation(title: "\(domain)", subtitle: "\(name)")
    }
}

struct SiteQuery: EntityStringQuery {
    func entities(for identifiers: [Int]) async throws -> [SiteEntity] {
        try await SiteDirectory.sites().filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [SiteEntity] {
        try await SiteDirectory.sites().filter { FuzzyMatcher.score(string, in: "\($0.domain) \($0.name)") != nil }
    }

    func suggestedEntities() async throws -> [SiteEntity] {
        try await SiteDirectory.sites()
    }
}

/// Sites from the running app's store, loading the list once when it is not there yet.
@MainActor
enum SiteDirectory {
    static func sites() async throws -> [SiteEntity] {
        let environment = try IntentSupport.environment()
        if environment.store.siteListings == nil {
            await environment.store.refresh(includeSiteList: true)
        }
        return (environment.store.siteListings ?? [])
            .filter { !$0.disabled }
            .map { SiteEntity(id: $0.id, domain: $0.domain, name: $0.name) }
    }
}

/// Shared checks for every intent.
@MainActor
enum IntentSupport {
    enum Failure: Error, CustomLocalizedStringResourceConvertible {
        case notRunning, signedOut, request(String)

        var localizedStringResource: LocalizedStringResource {
            switch self {
            case .notRunning:          return "Orchestrator is still starting. Try again in a moment."
            case .signedOut:           return "Sign in to Orchestrator first."
            case .request(let reason): return "\(reason)"
            }
        }
    }

    static func environment() throws -> AppEnvironment {
        guard let environment = AppEnvironment.current else { throw Failure.notRunning }
        guard environment.session.phase != .signedOut else { throw Failure.signedOut }
        return environment
    }

    /// Wraps an API error in a message Shortcuts can show.
    static func describe(_ error: Error) -> Failure {
        .request(APIError.wrap(error).errorDescription ?? "The request failed.")
    }
}
