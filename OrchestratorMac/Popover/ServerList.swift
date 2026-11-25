import OrchestratorKit
import SwiftUI

/// Server rows: mark, name, location and state, CPU and RAM meters.
struct ServerList: View {
    let environment: AppEnvironment
    var servers: [ServerStatus]

    var body: some View {
        if servers.isEmpty {
            EmptyRow(text: "No servers", symbol: "server.rack")
        } else {
            VStack(spacing: 0) {
                ForEach(Array(servers.enumerated()), id: \.element.id) { index, status in
                    if index > 0 { Divider() }
                    ServerRow(status: status)
                        .rightClickMenu { RowMenus.server(status.server, environment: environment) }
                }
            }
            .card()
        }
    }
}

private struct ServerRow: View {
    var status: ServerStatus

    var body: some View {
        Button {
            WebPanel.open(.server(id: status.server.id))
        } label: {
            HStack(spacing: 10) {
                StatusMarkView(mark: status.mark, size: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(status.server.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(status.mark == .healthy || status.mark == .unknown ? Color.secondary : status.mark.textTint)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                MiniMeter(label: "CPU", percent: status.server.cpuPercent)
                MiniMeter(label: "RAM", percent: status.server.ramPercent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open \(status.server.name) in the web panel")
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the server in the web panel")
    }

    private var detail: String {
        [status.server.location, status.label].compactMap { $0 }.joined(separator: " · ")
    }
}
