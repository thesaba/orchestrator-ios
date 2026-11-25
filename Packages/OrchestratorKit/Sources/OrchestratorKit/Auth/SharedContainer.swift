import Foundation

/// Where the token and shared state live, read from the host bundle's Info.plist.
///
/// The iOS app sets none of these keys, so it keeps its original behaviour: the bundle
/// identifier as keychain service, no access group, standard user defaults. The Mac app
/// and its widget extension set all three so they read the same token and settings.
///
/// | Info.plist key                       | Meaning                                   |
/// |--------------------------------------|-------------------------------------------|
/// | `OrchestratorKeychainService`        | keychain service shared by app + widget   |
/// | `OrchestratorKeychainAccessGroup`    | keychain access group (team-prefixed)     |
/// | `OrchestratorAppGroup`               | App Group for defaults and the snapshot   |
public enum SharedContainer {
    public static let keychainServiceKey = "OrchestratorKeychainService"
    public static let keychainAccessGroupKey = "OrchestratorKeychainAccessGroup"
    public static let appGroupKey = "OrchestratorAppGroup"

    public static var keychainService: String {
        infoString(keychainServiceKey) ?? Bundle.main.bundleIdentifier ?? "digital.abesadze.Orchestrator"
    }

    public static var keychainAccessGroup: String? {
        infoString(keychainAccessGroupKey)
    }

    public static var appGroup: String? {
        infoString(appGroupKey)
    }

    /// App Group defaults when configured, otherwise `.standard`.
    public static var defaults: UserDefaults {
        appGroup.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    /// The App Group container, for files shared with the widget extension.
    public static var containerURL: URL? {
        appGroup.flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
    }

    private static func infoString(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty, !value.hasPrefix("$(") else { return nil }
        return value
    }
}
