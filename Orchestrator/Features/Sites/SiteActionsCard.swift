import SwiftUI
import OrchestratorKit

/// The action surface for one site. Every destructive path goes through a confirmation
/// dialog, and every failure surfaces inline — nothing here fails quietly.
struct SiteActionsCard: View {
    let site: Site
    /// Called after any action that changes server state, so the detail screen refetches.
    var onChanged: () async -> Void

    @State private var runner = ActionRunner()
    @State private var showsDeploy = false
    @State private var confirmMaintenance = false
    @State private var confirmRedeploy: Deployment?

    var body: some View {
        VStack(spacing: 12) {
            ActionFeedbackView(runner: runner)

            SectionCard("Actions", systemImage: "bolt") {
                VStack(spacing: 0) {
                    Button {
                        showsDeploy = true
                    } label: {
                        row(
                            title: "Deploy",
                            subtitle: site.deployQueued ? "A deploy is queued" : "Branch \(site.branch ?? "main")",
                            systemImage: "arrow.up.circle.fill",
                            tint: .accentColor
                        )
                    }
                    .buttonStyle(.plain)

                    Divider()

                    Button {
                        confirmMaintenance = true
                    } label: {
                        row(
                            title: site.maintenanceMode ? "Turn maintenance off" : "Turn maintenance on",
                            subtitle: site.maintenanceMode
                                ? "Visitors currently see the maintenance page"
                                : "Visitors will see the maintenance page",
                            systemImage: "wrench.and.screwdriver.fill",
                            tint: site.maintenanceMode ? .green : .orange,
                            isBusy: runner.isRunning("maintenance")
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(runner.isRunning)

                    Divider()

                    NavigationLink { ReleasesView(site: site) } label: {
                        row(title: "Releases & rollback", subtitle: nil, systemImage: "clock.arrow.circlepath", tint: .purple, showsChevron: true)
                    }
                    .buttonStyle(.plain)

                    Divider()

                    NavigationLink { WorkersView(site: site) } label: {
                        row(title: "Workers & queue", subtitle: nil, systemImage: "gearshape.2.fill", tint: .teal, showsChevron: true)
                    }
                    .buttonStyle(.plain)

                    Divider()

                    NavigationLink { ArtisanView(site: site) } label: {
                        row(title: "Artisan", subtitle: nil, systemImage: "wand.and.stars", tint: .indigo, showsChevron: true)
                    }
                    .buttonStyle(.plain)

                    Divider()

                    NavigationLink { SiteLogsView(site: site) } label: {
                        row(title: "Laravel log", subtitle: nil, systemImage: "doc.text.magnifyingglass", tint: .brown, showsChevron: true)
                    }
                    .buttonStyle(.plain)

                    Divider()

                    NavigationLink { SiteConfigView(site: site) } label: {
                        row(title: "Configuration", subtitle: ".env, nginx, PHP, SSL, security", systemImage: "slider.horizontal.3", tint: .blue, showsChevron: true)
                    }
                    .buttonStyle(.plain)

                    Divider()

                    NavigationLink { FileManagerView(site: site) } label: {
                        row(title: "Files", subtitle: site.rootPath, systemImage: "folder.fill", tint: .cyan, showsChevron: true)
                    }
                    .buttonStyle(.plain)

                    Divider()

                    NavigationLink { DatabaseView(site: site) } label: {
                        row(title: "Database", subtitle: site.dbName, systemImage: "cylinder.fill", tint: .green, showsChevron: true)
                    }
                    .buttonStyle(.plain)

                    Divider()

                    NavigationLink { TerminalView(site: site) } label: {
                        row(title: "Terminal", subtitle: "Interactive shell over WebSocket", systemImage: "terminal.fill", tint: .primary, showsChevron: true)
                    }
                    .buttonStyle(.plain)

                    if let last = site.lastDeployment {
                        Divider()
                        Button {
                            confirmRedeploy = last
                        } label: {
                            row(
                                title: "Redeploy \(last.shortCommit)",
                                subtitle: "Re-run the last deployment",
                                systemImage: "arrow.triangle.2.circlepath",
                                tint: .orange,
                                isBusy: runner.isRunning("redeploy")
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(runner.isRunning)
                    }
                }
            }
        }
        .sheet(isPresented: $showsDeploy, onDismiss: { Task { await onChanged() } }) {
            DeployView(site: site)
        }
        .confirmationDialog(
            site.maintenanceMode ? "Bring \(site.domain) back online?" : "Put \(site.domain) into maintenance?",
            isPresented: $confirmMaintenance,
            titleVisibility: .visible
        ) {
            Button(site.maintenanceMode ? "Go live" : "Enable maintenance",
                   role: site.maintenanceMode ? nil : .destructive) {
                Task { await setMaintenance(!site.maintenanceMode) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(site.maintenanceMode
                 ? "Visitors will reach the site normally again."
                 : "Every visitor will see the maintenance page until you turn this off.")
        }
        .confirmationDialog(
            "Redeploy this commit?",
            isPresented: Binding(get: { confirmRedeploy != nil }, set: { if !$0 { confirmRedeploy = nil } }),
            titleVisibility: .visible,
            presenting: confirmRedeploy
        ) { deployment in
            Button("Redeploy \(deployment.shortCommit)", role: .destructive) {
                Task { await redeploy(deployment) }
            }
            Button("Cancel", role: .cancel) { confirmRedeploy = nil }
        } message: { deployment in
            Text("Runs the full pipeline again for \(deployment.branch ?? "the current branch") on the live site.")
        }
    }

    private func row(title: String,
                     subtitle: String?,
                     systemImage: String,
                     tint: Color,
                     isBusy: Bool = false,
                     showsChevron: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isBusy {
                ProgressView().controlSize(.small)
            } else if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.callout)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func setMaintenance(_ enabled: Bool) async {
        await runner.run(
            "maintenance",
            success: enabled ? "Maintenance mode is on." : "Site is live again."
        ) {
            try await OrchestratorAPI.shared.setMaintenance(siteID: site.id, enabled: enabled)
        } onSuccess: {
            await onChanged()
        }
    }

    private func redeploy(_ deployment: Deployment) async {
        confirmRedeploy = nil
        await runner.run("redeploy", success: "Redeploy started. Open Deploy to watch the log.") {
            try await OrchestratorAPI.shared.redeploy(siteID: site.id, deploymentID: deployment.id)
        } onSuccess: {
            await onChanged()
        }
    }
}
