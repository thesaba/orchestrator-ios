import AppIntents
import OrchestratorKit

/// Shortcuts actions that change production. Each asks the system confirmation first, with
/// the same consequence text as the app's own dialog; nothing runs if it is declined.
/// Rollback and maintenance mode are deliberately not offered here: they need Touch ID.

struct DeploySiteIntent: AppIntent {
    static let title: LocalizedStringResource = "Deploy Site"
    static let description = IntentDescription("Deploys a site's branch, or a given branch, tag or commit, after a confirmation.")

    @Parameter(title: "Site")
    var site: SiteEntity

    @Parameter(title: "Branch, Tag or Commit", description: "Leave empty to deploy the site's branch.")
    var ref: String?

    @Parameter(title: "Show Log", default: true)
    var showLog: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Deploy \(\.$site)") {
            \.$ref
            \.$showLog
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let environment = try IntentSupport.environment()
        let ref = ref?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let confirmation = environment.executor.deployConfirmation(siteID: site.id, ref: ref)
        try await requestConfirmation(actionName: .go, dialog: "\(confirmation.title) \(confirmation.consequence)")

        do {
            let reply = try await environment.executor.performDeploy(siteID: site.id, ref: ref, showLog: showLog)
            if reply.queued {
                return .result(dialog: "Deploy of \(site.domain) queued. It starts when the current deploy finishes.")
            }
            return .result(dialog: "Deploying \(site.domain).")
        } catch {
            throw IntentSupport.describe(error)
        }
    }
}

struct ClearCacheIntent: AppIntent {
    static let title: LocalizedStringResource = "Clear Site Cache"
    static let description = IntentDescription("Runs php artisan optimize:clear on a site, after a confirmation.")

    @Parameter(title: "Site")
    var site: SiteEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Clear the cache of \(\.$site)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await ArtisanIntentRunner.run("optimize:clear", on: site, from: self)
        return .result(dialog: "Clearing the cache of \(site.domain).")
    }
}

struct RestartQueueIntent: AppIntent {
    static let title: LocalizedStringResource = "Restart Site Queue"
    static let description = IntentDescription("Runs php artisan queue:restart on a site, after a confirmation.")

    @Parameter(title: "Site")
    var site: SiteEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Restart the queue of \(\.$site)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await ArtisanIntentRunner.run("queue:restart", on: site, from: self)
        return .result(dialog: "Restarting the queue workers of \(site.domain).")
    }
}

/// Clear cache and restart queue share the confirmation and the call.
@MainActor
enum ArtisanIntentRunner {
    static func run<Intent: AppIntent>(_ command: String, on site: SiteEntity, from intent: Intent) async throws {
        let environment = try IntentSupport.environment()
        let confirmation = environment.executor.artisanConfirmation(siteID: site.id, command: command)
        // Only non-destructive commands are offered as intents; destructive ones need Touch ID.
        guard !confirmation.requiresAuthentication else {
            throw IntentSupport.Failure.request("Run \(command) from Orchestrator itself; it needs Touch ID.")
        }
        try await intent.requestConfirmation(actionName: .run, dialog: "\(confirmation.title) \(confirmation.consequence)")
        do {
            try await environment.executor.performArtisan(siteID: site.id, command: command, showLog: true)
        } catch {
            throw IntentSupport.describe(error)
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
