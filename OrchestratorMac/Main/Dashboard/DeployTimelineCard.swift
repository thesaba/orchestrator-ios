import OrchestratorKit
import SwiftUI

/// The newest deployment of each site: a running one first with its step and progress.
struct DeployTimelineCard: View {
    let environment: AppEnvironment
    let model: MainWindowModel
    var deploys: [DashboardSummary.RecentDeploy]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Deploys", symbol: "arrow.up.circle.fill", tint: Vivid.blue, trailing: "All sites") { model.selection = .sites }
            if deploys.isEmpty {
                EmptyRow(text: "No deploys yet", symbol: "arrow.up.circle")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(deploys.enumerated()), id: \.element.id) { index, deploy in
                        if index > 0 { Divider() }
                        Group {
                            if deploy.outcome == .running {
                                RunningDeployRow(deploy: deploy) { showLog(deploy.siteID) }
                            } else {
                                FinishedDeployRow(deploy: deploy)
                            }
                        }
                        .contentShape(Rectangle())
                        .hoverHighlight()
                        .onTapGesture { model.openSite(deploy.siteID, tab: .deploys) }
                        .rightClickMenu {
                            if let site = environment.store.site(id: deploy.siteID) {
                                return RowMenus.site(site, environment: environment)
                            }
                            return NSMenu()
                        }
                    }
                }
                .card()
            }
        }
    }

    private func showLog(_ siteID: Int) {
        if let site = environment.store.site(id: siteID) {
            environment.logs.showLiveDeploy(for: site)
        }
    }
}

private struct RunningDeployRow: View {
    var deploy: DashboardSummary.RecentDeploy
    var showLog: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                StatusMarkView(mark: .deploying, size: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(deploy.domain)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.accentText)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                Button("Show log", action: showLog)
                    .buttonStyle(RowButtonStyle(prominent: true))
                    .accessibilityLabel("Show the deploy log of \(deploy.domain)")
            }
            if let progress = deploy.progress {
                ProgressBar(fraction: progress, tint: .brandTeal)
                    .accessibilityElement()
                    .accessibilityLabel("Deploy progress")
                    .accessibilityValue("\(Int(progress * 100)) percent")
            } else {
                ProgressView().progressViewStyle(.linear).controlSize(.mini)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.tintInfo)
    }

    private var detail: String {
        guard let step = deploy.currentStep else { return "Deploying" }
        return "Deploying · step \(step.number) of \(deploy.totalSteps ?? step.total) · \(step.title)"
    }
}

private struct FinishedDeployRow: View {
    var deploy: DashboardSummary.RecentDeploy

    var body: some View {
        HStack(spacing: 10) {
            outcomeIcon
            HStack(spacing: 6) {
                Text(deploy.domain)
                    .font(.system(size: 13, weight: .medium))
                Text(reference)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            if let date = deploy.startedAt {
                Text(RelativeTime.ago(date))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Text(deploy.durationSeconds.map(DurationText.short) ?? "")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .accessibilityElement(children: .combine)
    }

    private var reference: String {
        [deploy.branch, deploy.shortCommit].compactMap { $0 }.joined(separator: " · ")
    }

    @ViewBuilder
    private var outcomeIcon: some View {
        switch deploy.outcome {
        case .succeeded:
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.statusSuccess)
                .frame(width: 16)
                .accessibilityLabel("Succeeded")
        case .failed:
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.statusDanger)
                .frame(width: 16)
                .accessibilityLabel("Failed")
        default:
            StatusMarkView(mark: .unknown, size: 16)
        }
    }
}
