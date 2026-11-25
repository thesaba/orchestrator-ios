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
                    AttentionRow(item: item) { siteID in
                        let executor = environment.executor
                        Task { await executor.renewCertificate(siteID: siteID) }
                    }
                }
            }
            .card(tint: items.contains { $0.severity == .failure } ? .tintDanger : .tintWarning)
        }
    }
}

private struct AttentionRow: View {
    var item: AttentionItem
    var renew: (Int) -> Void

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
                if case .certificate(let siteID) = item.subject { renew(siteID) } else { WebPanel.open(destination) }
            }
            .buttonStyle(RowButtonStyle())
            .help(isCertificate ? "Renew the certificate (asks for confirmation)" : "Open in the web panel")
            .accessibilityLabel(isCertificate ? "Renew the certificate of \(item.source)" : "View \(item.source) in the web panel")
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

    private var destination: WebPanel.Destination {
        switch item.subject {
        case .server(let id, _, _):   return .server(id: id)
        case .certificate(let id):    return .site(id: id)
        case .siteDown(let id):       return .site(id: id)
        }
    }
}
