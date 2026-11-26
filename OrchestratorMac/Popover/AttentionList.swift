import OrchestratorKit
import SwiftUI

/// Tinted card with one row per alert. "Renew" asks for confirmation; "View" opens the web panel.
struct AttentionList: View {
    let environment: AppEnvironment
    var items: [AttentionItem]

    var body: some View {
        if items.isEmpty {
            EmptyRow(text: "No open alerts", symbol: "checkmark.circle")
        } else {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider() }
                    AttentionRow(item: item, renew: { siteID in
                        let executor = environment.executor
                        Task { await executor.renewCertificate(siteID: siteID) }
                    }, view: { environment.open($0) })
                }
            }
            .card(tint: items.contains { $0.severity == .failure } ? .tintDanger : .tintWarning)
        }
    }
}

private struct AttentionRow: View {
    var item: AttentionItem
    var renew: (Int) -> Void
    /// Opens the server's or site's page in the main window.
    var view: (DeepLink) -> Void

    var body: some View {
        HStack(spacing: 10) {
            StatusMarkView(mark: item.severity, size: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            Button(buttonTitle) {
                if case .certificate(let siteID) = item.subject { renew(siteID) } else { view(destination) }
            }
            .buttonStyle(RowButtonStyle())
            .help(isCertificate ? "Renew the certificate (asks for confirmation)" : "Open \(item.source)")
            .accessibilityLabel(isCertificate ? "Renew the certificate of \(item.source)" : "View \(item.source)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var subtitle: String {
        guard let since = item.since else { return item.source }
        return "\(item.source) · \(RelativeTime.ago(since))"
    }

    private var isCertificate: Bool {
        if case .certificate = item.subject { return true }
        return false
    }

    private var buttonTitle: String { isCertificate ? "Renew" : "View" }

    private var destination: DeepLink {
        switch item.subject {
        case .server(let id, _, _):   return .server(serverID: id)
        case .certificate(let id):    return .siteTab(siteID: id, tab: "ssl")
        case .siteDown(let id):       return .site(siteID: id)
        }
    }
}
