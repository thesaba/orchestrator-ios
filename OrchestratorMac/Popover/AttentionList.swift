import OrchestratorKit
import SwiftUI

/// Tinted card with one row per alert. In this phase the buttons only open the web panel.
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
                    AttentionRow(item: item)
                }
            }
            .card(tint: items.contains { $0.severity == .failure } ? .tintDanger : .tintWarning)
        }
    }
}

private struct AttentionRow: View {
    var item: AttentionItem

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

            Button(buttonTitle) { WebPanel.open(destination) }
                .buttonStyle(RowButtonStyle())
                .help("Open in the web panel")
                .accessibilityLabel("\(buttonTitle) \(item.source) in the web panel")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var subtitle: String {
        guard let since = item.since else { return item.source }
        return "\(item.source) · \(RelativeTime.ago(since))"
    }

    private var buttonTitle: String {
        if case .certificate = item.subject { return "Renew" }
        return "View"
    }

    private var destination: WebPanel.Destination {
        switch item.subject {
        case .server(let id, _, _):   return .server(id: id)
        case .certificate(let id):    return .site(id: id)
        case .siteDown(let id):       return .site(id: id)
        }
    }
}
