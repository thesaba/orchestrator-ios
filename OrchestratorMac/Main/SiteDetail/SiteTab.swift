import Foundation

/// The tabs across the top of a site's page.
enum SiteTab: String, CaseIterable, Identifiable, Hashable {
    case overview, deploys, config, ssl, workers, logs, artisan
    case files, database, security

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .deploys:  return "Deploys"
        case .config:   return "Config"
        case .ssl:      return "SSL"
        case .workers:  return "Workers"
        case .logs:     return "Logs"
        case .artisan:  return "Artisan"
        case .files:    return "Files"
        case .database: return "Database"
        case .security: return "Security"
        }
    }
}
