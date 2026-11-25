import AppKit
import OrchestratorKit

/// The single path from a user action to the API.
///
/// Every action that changes production shows a confirmation naming its consequence first;
/// rollback, maintenance mode and destructive Artisan commands then also require Touch ID
/// or the account password. Nothing here runs on its own: every entry point is a click,
/// a key press in the palette or a notification button.
@MainActor
final class CommandExecutor {
    private let environment: AppEnvironment
    private let api: OrchestratorAPI

    init(environment: AppEnvironment, api: OrchestratorAPI = .shared) {
        self.environment = environment
        self.api = api
    }

    private var store: MonitorStore { environment.store }
    private var logs: LogCoordinator { environment.logs }

    // MARK: - Palette entry point

    /// - Parameter showFullLog: ⌘Return — open the full log window instead of the compact panel.
    func run(_ command: PaletteCommand, showFullLog: Bool = false) async {
        environment.settings.recordRecent(command.id)
        switch command.kind {
        case .deploy(let siteID):                  await deploy(siteID: siteID, ref: nil, showFullLog: showFullLog)
        case .rollback(let siteID):                await rollback(siteID: siteID, showFullLog: showFullLog)
        case .clearCache(let siteID):              await runArtisan(siteID: siteID, command: "optimize:clear", showFullLog: showFullLog)
        case .restartQueue(let siteID):            await runArtisan(siteID: siteID, command: "queue:restart", showFullLog: showFullLog)
        case .maintenance(let siteID, let enable): await setMaintenance(siteID: siteID, enable: enable)
        case .renewCertificate(let siteID):        await renewCertificate(siteID: siteID)
        case .artisan:                             break // handled by the palette's command picker
        case .ssh(let serverID):                   await openSSH(serverID: serverID)
        case .siteLogs(let siteID):                environment.windows.showSiteLogs(siteID: siteID, domain: domain(of: siteID))
        case .lastDeployLog(let siteID):           logs.showWindow(siteID: siteID, domain: domain(of: siteID))
        case .openSite(let siteID):                WebPanel.open(.site(id: siteID))
        case .openServer(let serverID):            WebPanel.open(.server(id: serverID))
        }
    }

    // MARK: - Deploy

    func deploy(siteID: Int, ref: String?, showFullLog: Bool = false) async {
        let site = listing(siteID)
        let domain = domain(of: siteID)
        let what = ref.map { "\($0)" } ?? site?.branch.map { "the latest commit of \($0)" } ?? "the latest commit"
        let confirmation = Confirmation(
            title: "Deploy \(domain)?",
            consequence: "Ships \(what) to \(domain). Dependencies install, migrations run and the site "
                + "switches to the new release at the end. If a deploy is already running, this one is queued.",
            confirmTitle: "Deploy"
        )
        guard await confirm(confirmation, reason: "deploy \(domain)") else { return }

        do {
            let reply = try await api.requestDeploy(siteID: siteID, ref: ref)
            environment.scheduler.requestSiteList()
            if reply.queued {
                environment.notifications.postInfo(title: "Deploy queued · \(domain)",
                                                   body: reply.message ?? "It starts when the current deploy finishes.")
                return
            }
            let session = LogSession(siteID: siteID, domain: domain, kind: .deploy,
                                     branch: ref ?? site?.branch, deploymentID: reply.deploymentId)
            logs.start(session, showFullLog: showFullLog)
        } catch {
            AlertPresenter.showError("Could not deploy \(domain)", APIError.wrap(error).errorDescription)
        }
    }

    /// Retry after a failed deploy: the same branch again, so a fix pushed meanwhile ships.
    func retryDeploy(siteID: Int) async {
        await deploy(siteID: siteID, ref: listing(siteID)?.branch, showFullLog: true)
    }

    // MARK: - Rollback

    func rollback(siteID: Int, showFullLog: Bool = false) async {
        let domain = domain(of: siteID)
        let releases: ReleasesResponse
        do {
            releases = try await api.releases(siteID: siteID)
        } catch {
            AlertPresenter.showError("Could not load the releases of \(domain)", APIError.wrap(error).errorDescription)
            return
        }
        let current = releases.current ?? releases.releases.first(where: \.isCurrent)?.name
        let older = releases.releases
            .map(\.name)
            .filter { name in current.map { name < $0 } ?? true }
            .sorted(by: >)
        guard let target = older.first else {
            AlertPresenter.showInfo("Nothing to roll back to", "\(domain) has no release older than the live one.")
            return
        }
        let when = releases.releases.first { $0.name == target }?.createdAt
            .map { "release " + $0.formatted(.dateTime.day().month(.abbreviated).hour().minute()) }
            ?? ReleaseName.display(target)

        let confirmation = Confirmation(
            title: "Roll back \(domain)?",
            consequence: "\(domain) switches back to \(when). Database migrations are not reverted, so the "
                + "older code runs against the current schema. Queue workers restart.",
            confirmTitle: "Roll Back",
            isDestructive: true,
            requiresAuthentication: true
        )
        guard await confirm(confirmation, reason: "roll back \(domain)") else { return }

        do {
            let reply = try await api.requestRollback(siteID: siteID, release: target)
            environment.scheduler.requestSiteList()
            let session = LogSession(siteID: siteID, domain: domain, kind: .rollback(release: target),
                                     deploymentID: reply.deploymentId)
            logs.start(session, showFullLog: showFullLog)
        } catch {
            AlertPresenter.showError("Could not roll back \(domain)", APIError.wrap(error).errorDescription)
        }
    }

    // MARK: - Artisan

    func runArtisan(siteID: Int, command: String, showFullLog: Bool = false) async {
        let domain = domain(of: siteID)
        var consequence: String
        switch command {
        case "optimize:clear":
            consequence = "Runs php artisan optimize:clear on \(domain). Config, route, view and application "
                + "caches are cleared; the first requests afterwards are slower while they rebuild."
        case "queue:restart":
            consequence = "Runs php artisan queue:restart on \(domain). Workers finish their current job, "
                + "then restart with the current code."
        default:
            consequence = "Runs php artisan \(command) on \(domain)."
        }
        if ArtisanSafety.isDataLoss(command) {
            consequence += " This command can delete or change data in the production database. Make sure a recent backup exists."
        } else if ArtisanSafety.needsAuthentication(command) {
            consequence += " It changes the production database or stops running workers."
        }
        let destructive = ArtisanSafety.needsAuthentication(command)
        let confirmation = Confirmation(
            title: "Run \(command) on \(domain)?",
            consequence: consequence,
            confirmTitle: "Run",
            isDestructive: destructive,
            requiresAuthentication: destructive
        )
        guard await confirm(confirmation, reason: "run \(command) on \(domain)") else { return }

        do {
            try await api.runArtisan(siteID: siteID, command: command)
            logs.start(LogSession(siteID: siteID, domain: domain, kind: .artisan(command: command)),
                       showFullLog: false)
        } catch {
            AlertPresenter.showError("Could not run \(command)", APIError.wrap(error).errorDescription)
        }
    }

    // MARK: - Maintenance

    func setMaintenance(siteID: Int, enable: Bool) async {
        let domain = domain(of: siteID)
        let confirmation = enable
            ? Confirmation(
                title: "Turn on maintenance mode for \(domain)?",
                consequence: "Every visitor of \(domain) sees the maintenance page until maintenance mode is turned off.",
                confirmTitle: "Turn On", isDestructive: true, requiresAuthentication: true)
            : Confirmation(
                title: "Turn off maintenance mode for \(domain)?",
                consequence: "\(domain) serves visitors again with the code that is live now.",
                confirmTitle: "Turn Off", requiresAuthentication: true)
        guard await confirm(confirmation, reason: enable ? "put \(domain) into maintenance mode" : "bring \(domain) back online") else { return }

        do {
            let result = try await api.requestMaintenance(siteID: siteID, enabled: enable)
            environment.scheduler.requestSiteList()
            environment.notifications.postInfo(
                title: enable ? "Maintenance mode on · \(domain)" : "Maintenance mode off · \(domain)",
                body: result.output?.isEmpty == false ? result.output! : (enable ? "Visitors see the maintenance page." : "The site serves visitors again."))
        } catch {
            AlertPresenter.showError("Could not change maintenance mode", APIError.wrap(error).errorDescription)
        }
    }

    // MARK: - Certificates

    func renewCertificate(siteID: Int) async {
        let domain = domain(of: siteID)
        let confirmation = Confirmation(
            title: "Renew the certificate of \(domain)?",
            consequence: "Runs certbot renew for \(domain). Nginx reloads when the certificate is replaced; the site stays online.",
            confirmTitle: "Renew"
        )
        guard await confirm(confirmation, reason: "renew the certificate of \(domain)") else { return }
        do {
            try await api.renewSSL(siteID: siteID)
            logs.start(LogSession(siteID: siteID, domain: domain, kind: .certificate), showFullLog: false)
        } catch {
            AlertPresenter.showError("Could not renew the certificate", APIError.wrap(error).errorDescription)
        }
    }

    // MARK: - SSH (opens Terminal; changes nothing)

    func openSSH(serverID: Int) async {
        let fleet = store.servers.first { $0.id == serverID }
        var user = environment.settings.localSSHUser
        var host = APIConfig.baseURL.host() ?? ""
        var port = 22

        if fleet?.isLocal != true {
            do {
                guard let server = try await api.servers().first(where: { $0.id == serverID }), let address = server.host else {
                    AlertPresenter.showError("No SSH address", "The panel has no SSH host for \(fleet?.name ?? "this server").")
                    return
                }
                host = address
                user = server.sshUser ?? "root"
                port = server.port ?? 22
            } catch {
                AlertPresenter.showError("Could not load the server's SSH address", APIError.wrap(error).errorDescription)
                return
            }
        }

        var components = URLComponents()
        components.scheme = "ssh"
        components.user = user
        components.host = host
        if port != 22 { components.port = port }
        guard let url = components.url else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Helpers

    /// Confirmation, then Touch ID or the password when the action asks for it.
    private func confirm(_ confirmation: Confirmation, reason: String) async -> Bool {
        environment.statusItem?.closePopover()
        guard AlertPresenter.confirm(confirmation) else { return false }
        guard confirmation.requiresAuthentication else { return true }
        return await ActionAuthorizer.authorize(reason: reason)
    }

    private func listing(_ siteID: Int) -> SiteListing? {
        store.siteListings?.first { $0.id == siteID }
    }

    func domain(of siteID: Int) -> String {
        listing(siteID)?.domain ?? store.site(id: siteID)?.domain ?? "site \(siteID)"
    }
}
