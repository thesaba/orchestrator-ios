import OrchestratorKit
import SwiftUI

/// What is waiting to ship, the deploy actions, and the full deploy log with its history:
/// the same view as the deploy log window, inside the page.
struct SiteDeploysTab: View {
    let environment: AppEnvironment
    var row: SiteTableRow

    @State private var logModel: DeployLogWindowModel?
    @State private var pending: DeployPending?
    @State private var pendingError: String?

    private var executor: CommandExecutor { environment.executor }

    var body: some View {
        VStack(spacing: 0) {
            pendingStrip
            Divider()
            if let logModel {
                DeployLogWindowView(model: logModel, onShrink: {}, embedded: true)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: row.id) { await load() }
        // A deploy that starts while the tab is open is followed here too.
        .onChange(of: row.isDeploying) { _, deploying in
            if deploying, let site = environment.store.site(id: row.id) {
                environment.logs.attachInline(toDeployOf: site)
            }
            if !deploying { logModel?.reloadHistory() }
        }
    }

    private func load() async {
        // Following a running deploy is what opening this tab asks for.
        if row.isDeploying, let site = environment.store.site(id: row.id) {
            environment.logs.attachInline(toDeployOf: site)
        }
        let model = DeployLogWindowModel(siteID: row.id, domain: row.domain, environment: environment)
        logModel = model
        async let history: Void = model.load()
        async let waiting = try? environment.api.deployPending(siteID: row.id)
        pending = await waiting
        pendingError = pending == nil ? "Could not compare with the remote branch." : nil
        await history
    }

    private var pendingStrip: some View {
        HStack(spacing: 10) {
            Image(systemName: pendingSymbol)
                .foregroundStyle(pending?.upToDate == false ? Color.accentText : .secondary)
            Text(pendingText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Button("Deploy Branch, Tag or Commit…") {
                let id = row.id
                Task { await executor.deployChoosingRef(siteID: id) }
            }
            Button("Roll Back…") {
                let id = row.id
                Task { await executor.rollback(siteID: id) }
            }
            .help("Asks for confirmation and Touch ID")
            Button(row.isDeploying ? "Deploying…" : "Deploy…") {
                let id = row.id
                Task { await executor.deploy(siteID: id, ref: nil) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(row.isDeploying)
        }
        .controlSize(.small)
        .padding(.horizontal, 16)
        .frame(height: 40)
    }

    private var pendingSymbol: String {
        guard let pending else { return "questionmark.circle" }
        return pending.upToDate ? "checkmark.circle" : "arrow.up.circle"
    }

    private var pendingText: String {
        guard let pending else { return pendingError ?? "Checking the remote branch…" }
        let branch = pending.branch ?? row.branch ?? "the branch"
        if pending.upToDate { return "Up to date with \(branch) · live \(pending.shortCurrent)" }
        let count = pending.commits.count
        let commits = count == 0 ? "New commits" : (count == 1 ? "1 commit" : "\(count) commits")
        return "\(commits) waiting on \(branch) · live \(pending.shortCurrent) → \(pending.shortRemote)"
    }
}
