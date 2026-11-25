import Foundation

/// Which Artisan commands are dangerous on production.
public enum ArtisanSafety {
    /// Commands that can lose data if run against production.
    public static let dataLoss: Set<String> = [
        "migrate:fresh", "migrate:refresh", "migrate:reset", "migrate:rollback",
        "db:wipe", "db:seed", "cache:forget", "queue:flush"
    ]

    /// Commands that change the schema, delete records or stop workers. The Mac app asks for
    /// Touch ID or the account password before running any of these.
    public static let requiresAuthentication: Set<String> = dataLoss.union([
        "migrate", "telescope:clear", "horizon:terminate"
    ])

    public static func isDataLoss(_ command: String) -> Bool {
        dataLoss.contains(root(of: command))
    }

    public static func needsAuthentication(_ command: String) -> Bool {
        requiresAuthentication.contains(root(of: command))
    }

    private static func root(of command: String) -> String {
        command.split(separator: " ").first.map(String.init) ?? command
    }
}
