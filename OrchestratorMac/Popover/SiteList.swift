import OrchestratorKit
import SwiftUI

/// Site rows. A deploying site gets the tinted row with its current step and progress.
///
/// Read-only for now: "Deploy" and "Show log" open the site in the web panel. Deploying from
/// the Mac and the in-app log arrive with the confirmation flow.
struct SiteList: View {
    let environment: AppEnvironment
    var sites: [SiteStatus]

    var body: some View {
        if sites.isEmpty {
            EmptyRow(text: "No sites", symbol: "globe")
        } else {
            VStack(spacing: 0) {
                ForEach(Array(sites.enumerated()), id: \.element.id) { index, site in
                    if index > 0 { Divider() }
                    if site.isDeploying {
                        DeployingSiteRow(site: site)
                    } else {
                        SiteRow(site: site)
                    }
                }
            }
            .card()
        }
    }
}

private struct SiteRow: View {
    var site: SiteStatus

    var body: some View {
        HStack(spacing: 10) {
            StatusMarkView(mark: site.mark, size: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(site.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(site.mark == .failure ? site.mark.textTint : .secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            Button("Deploy") { WebPanel.open(.site(id: site.id)) }
                .buttonStyle(RowButtonStyle())
                .help("Open \(site.domain) in the web panel to deploy")
                .accessibilityLabel("Deploy \(site.name) in the web panel")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private var detail: String {
        var parts: [String] = []
        if site.mark == .failure || site.mark == .unknown { parts.append(site.label) }
        if let branch = site.branch { parts.append(branch) }
        if let commit = site.shortCommit { parts.append(commit) }
        if let date = site.lastDeployAt {
            let verb = site.lastDeployStatus == "failed" ? "failed" : "deployed"
            parts.append("\(verb) \(RelativeTime.ago(date))")
        }
        if parts.isEmpty { parts.append(site.label) }
        return parts.joined(separator: " · ")
    }
}

private struct DeployingSiteRow: View {
    var site: SiteStatus

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 10) {
                StatusMarkView(mark: .deploying, size: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(site.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.accentText)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)

                Button("Show log") { WebPanel.open(.site(id: site.id)) }
                    .buttonStyle(RowButtonStyle(prominent: true))
                    .help("Open the running deploy in the web panel")
                    .accessibilityLabel("Show the deploy log of \(site.name) in the web panel")
            }
            if let progress = site.deploy?.progress {
                ProgressBar(fraction: progress)
                    .accessibilityElement()
                    .accessibilityLabel("Deploy progress")
                    .accessibilityValue("\(Int(progress * 100)) percent")
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
                    .controlSize(.mini)
                    .accessibilityLabel("Deploying")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.tintInfo)
    }

    private var detail: String {
        guard let summary = site.deploy, let step = summary.currentStep else { return "Deploying" }
        return "Deploying · step \(step.number) of \(step.total) · \(step.title)"
    }
}
