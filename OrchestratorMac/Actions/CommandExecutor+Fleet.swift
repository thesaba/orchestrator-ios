import AppKit
import OrchestratorKit

/// The fixed actions a fleet server accepts (services, reboot, packages, containers). Each
/// names its consequence first; stopping, rebooting and upgrading also need Touch ID. The
/// result is read back from the run (GET) and shown when it finishes.
extension CommandExecutor {
    func runFleetAction(serverID: Int, serverName: String, _ action: FleetAction) async -> Bool {
        let confirmation = Confirmation(title: "\(action.title) on \(serverName)?",
                                        consequence: consequence(of: action, on: serverName),
                                        confirmTitle: confirmTitle(action),
                                        isDestructive: action.isDestructive,
                                        requiresAuthentication: action.isDestructive)
        guard await confirm(confirmation, reason: "\(action.title.lowercased()) on \(serverName)") else { return false }
        do {
            let runID = try await api.startFleetAction(serverID: serverID, action)
            Task { await self.report(runID: runID, action: action, serverName: serverName) }
            return true
        } catch {
            AlertPresenter.showError("Could not \(action.title.lowercased()) on \(serverName)", APIError.wrap(error).errorDescription)
            return false
        }
    }

    private func confirmTitle(_ action: FleetAction) -> String {
        switch action {
        case .service(let verb, _):      return verb.rawValue.capitalized
        case .container(let verb, _, _): return verb.rawValue.capitalized
        case .reboot:                    return "Reboot"
        case .cancelReboot:              return "Cancel Reboot"
        case .updatePackages:            return "Update"
        }
    }

    private func consequence(of action: FleetAction, on server: String) -> String {
        switch action {
        case .service(.stop, let name):
            return "Stops \(name) on \(server). Everything that depends on it stops working until it is started again."
        case .service(.restart, let name):
            return "Restarts \(name) on \(server). Requests in flight can fail for a few seconds."
        case .service(.reload, let name):
            return "Reloads the configuration of \(name) on \(server) without stopping it."
        case .service(.start, let name):
            return "Starts \(name) on \(server)."
        case .reboot(let delay):
            return (delay > 0 ? "Schedules a reboot of \(server) in \(delay) minutes. " : "Reboots \(server) now. ")
                + "Every site and service on it is offline until it is back, usually one to three minutes."
        case .cancelReboot:
            return "Cancels the reboot scheduled on \(server)."
        case .updatePackages(let dist):
            return "Runs apt \(dist ? "dist-upgrade" : "upgrade") on \(server). Services restart as packages update, "
                + "and some updates need a reboot afterwards."
        case .container(.stop, _, let name):
            return "Stops the container \(name) on \(server); what it serves goes offline."
        case .container(let verb, _, let name):
            return "\(verb.rawValue.capitalized)s the container \(name) on \(server)."
        }
    }

    /// Polls the run until it finishes (at most about two minutes) and reports the outcome.
    private func report(runID: Int, action: FleetAction, serverName: String) async {
        for _ in 0..<80 {
            try? await Task.sleep(for: .seconds(1.5))
            guard let run = try? await api.fleetRun(id: runID) else { continue }
            guard run.isFinished, let target = run.targets.first else { continue }
            let output = (target.output ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let ok = target.status == "success"
            environment.notifications.postInfo(
                title: "\(action.title) · \(serverName) · \(ok ? "done" : target.status)",
                body: output.isEmpty ? (ok ? "Finished." : "Exit code \(target.exitCode.map(String.init) ?? "unknown").")
                                     : String(output.suffix(400)))
            return
        }
    }
}
