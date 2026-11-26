import AppKit
import OrchestratorKit

/// Write paths of a site's page. Same rules as the rest of `CommandExecutor`: every call is
/// a click, each names its consequence before it runs, and changes that can take a site
/// down or expose secrets also need Touch ID or the password.
extension CommandExecutor {
    // MARK: - .env

    /// Touch ID before secret values are shown. No dialog: showing changes nothing.
    func authorizeRevealingSecrets(siteID: Int) async -> Bool {
        await ActionAuthorizer.authorize(reason: "show the secrets in the .env of \(domain(of: siteID))")
    }

    /// Saves the edited `.env`. - Returns: true when the panel accepted it.
    func saveEnv(siteID: Int, original: String, content: String) async -> Bool {
        let domain = domain(of: siteID)
        let changes = EnvChange.between(original, content)
        let list = changes.isEmpty ? "Only formatting or comments change." :
            "Changes: " + changes.prefix(8).map(\.summary).joined(separator: ", ")
            + (changes.count > 8 ? " and \(changes.count - 8) more." : ".")
        let confirmation = Confirmation(
            title: "Save the .env of \(domain)?",
            consequence: "\(list) The file is written on the server and a version is kept, so it can be restored. "
                + "Laravel reads cached config until the cache is cleared: run config:clear or optimize:clear "
                + "afterwards. A wrong value can take \(domain) down.",
            confirmTitle: "Save",
            isDestructive: true,
            requiresAuthentication: true)
        guard await confirm(confirmation, reason: "change the .env of \(domain)") else { return false }
        do {
            try await api.saveConfigFile(.env, siteID: siteID, content: content)
            return true
        } catch {
            AlertPresenter.showError("Could not save the .env of \(domain)", APIError.wrap(error).errorDescription)
            return false
        }
    }

    /// Restores an older `.env` version. - Returns: true when the panel accepted it.
    func restoreEnv(siteID: Int, version: EnvVersion) async -> Bool {
        let domain = domain(of: siteID)
        let when = version.createdAt?.formatted(date: .abbreviated, time: .shortened) ?? "version \(version.id)"
        let confirmation = Confirmation(
            title: "Restore the .env of \(domain) from \(when)?",
            consequence: "The whole .env is replaced with the version saved \(when) by \(version.authorEmail). "
                + "The current file is kept as a version first. Clear the config cache afterwards.",
            confirmTitle: "Restore",
            isDestructive: true,
            requiresAuthentication: true)
        guard await confirm(confirmation, reason: "restore the .env of \(domain)") else { return false }
        do {
            try await api.restoreEnvVersion(siteID: siteID, versionID: version.id)
            return true
        } catch {
            AlertPresenter.showError("Could not restore the .env", APIError.wrap(error).errorDescription)
            return false
        }
    }

    // MARK: - Certificates

    func issueCertificate(siteID: Int) async {
        let domain = domain(of: siteID)
        let confirmation = Confirmation(
            title: "Issue a certificate for \(domain)?",
            consequence: "Runs certbot for \(domain) and the host names in its nginx config that resolve to this server. "
                + "Nginx reloads when the certificate is installed. Let’s Encrypt limits how often this can be repeated.",
            confirmTitle: "Issue")
        guard await confirm(confirmation, reason: "issue a certificate for \(domain)") else { return }
        do {
            try await api.issueSSL(siteID: siteID)
            environment.logs.start(LogSession(siteID: siteID, domain: domain, kind: .certificate), showFullLog: false)
        } catch {
            AlertPresenter.showError("Could not issue the certificate", APIError.wrap(error).errorDescription)
        }
    }

    // MARK: - Workers

    /// Start, stop or restart every Supervisor worker of the site (the panel has no per-process control).
    func controlWorkers(siteID: Int, action: OrchestratorAPI.SupervisorAction) async -> Bool {
        let domain = domain(of: siteID)
        let consequence: String
        switch action {
        case .start:   consequence = "Starts every queue worker of \(domain)."
        case .restart: consequence = "Restarts every queue worker of \(domain). Jobs in progress are interrupted and retried."
        case .stop:    consequence = "Stops every queue worker of \(domain). Queued jobs wait until the workers start again, so mail, payments and other background work stop."
        }
        let confirmation = Confirmation(
            title: "\(action.title) the workers of \(domain)?", consequence: consequence,
            confirmTitle: action.title, isDestructive: action.isDestructive,
            requiresAuthentication: action.isDestructive)
        guard await confirm(confirmation, reason: "\(action.rawValue) the workers of \(domain)") else { return false }
        do {
            try await api.controlSupervisor(siteID: siteID, action: action)
            return true
        } catch {
            AlertPresenter.showError("Could not \(action.rawValue) the workers", APIError.wrap(error).errorDescription)
            return false
        }
    }

    func retryFailedJob(siteID: Int, job: FailedJob) async -> Bool {
        let domain = domain(of: siteID)
        let confirmation = Confirmation(
            title: "Retry \(job.jobName ?? "this job")?",
            consequence: "Puts the job back on the \(job.queue ?? "default") queue of \(domain). It runs again, "
                + "so anything it does (an email, a payment call) can happen a second time.",
            confirmTitle: "Retry")
        guard await confirm(confirmation, reason: "retry a job on \(domain)") else { return false }
        do {
            try await api.retryFailedJob(siteID: siteID, jobID: job.id)
            return true
        } catch {
            AlertPresenter.showError("Could not retry the job", APIError.wrap(error).errorDescription)
            return false
        }
    }

    func retryAllFailedJobs(siteID: Int, count: Int) async -> Bool {
        let domain = domain(of: siteID)
        let confirmation = Confirmation(
            title: "Retry \(count == 1 ? "1 failed job" : "all \(count) failed jobs") of \(domain)?",
            consequence: "Every failed job goes back on its queue and runs again, so emails or payment calls in "
                + "them can happen a second time.",
            confirmTitle: "Retry All")
        guard await confirm(confirmation, reason: "retry the failed jobs of \(domain)") else { return false }
        do {
            try await api.retryAllFailedJobs(siteID: siteID)
            return true
        } catch {
            AlertPresenter.showError("Could not retry the jobs", APIError.wrap(error).errorDescription)
            return false
        }
    }

    // MARK: - Artisan inside the page

    /// Like `runArtisan`, with the output shown in the Artisan tab instead of a panel.
    func runArtisanInline(siteID: Int, command: String) async {
        let domain = domain(of: siteID)
        guard await confirm(artisanConfirmation(siteID: siteID, command: command),
                            reason: "run \(command) on \(domain)") else { return }
        do {
            try await performArtisan(siteID: siteID, command: command, showLog: false)
            environment.logs.startInline(LogSession(siteID: siteID, domain: domain, kind: .artisan(command: command)))
        } catch {
            AlertPresenter.showError("Could not run \(command)", APIError.wrap(error).errorDescription)
        }
    }
}
