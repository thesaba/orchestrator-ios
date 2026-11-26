import OrchestratorKit
import OrchestratorTerminal
import SwiftUI

/// A live shell in the window: the status strip with Reconnect and Disconnect above a
/// SwiftTerm terminal. `makeURL` builds the WebSocket address when (re)connecting.
struct TerminalPane: View {
    var title: String
    var warning: String
    var makeURL: () -> URL?

    @State private var connection: TerminalConnection?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                statusDot
                Text(statusText).font(.system(size: 12)).lineLimit(1)
                Spacer()
                Text(warning).font(.system(size: 11)).foregroundStyle(Color.statusWarningText).lineLimit(1)
                if let connection, connection.state == .connected {
                    Button("Disconnect") { connection.disconnect() }
                } else {
                    Button("Reconnect") { connect() }
                        .disabled(connection?.state == .connecting)
                }
            }
            .controlSize(.small)
            .padding(.horizontal, 14)
            .frame(height: 34)
            Divider()
            if let connection {
                TerminalSessionView(connection: connection)
                    .padding(6)
                    .background(Color(red: 0.08, green: 0.08, blue: 0.09))
            }
        }
        .onAppear { if connection == nil { connect() } }
        .onDisappear { connection?.disconnect() }
    }

    private func connect() {
        guard let url = makeURL() else { return }
        connection?.disconnect()
        let next = TerminalConnection(url: url)
        connection = next
        next.connect()
    }

    @ViewBuilder
    private var statusDot: some View {
        switch connection?.state {
        case .connected?:
            Circle().fill(Color.statusSuccess).frame(width: 8, height: 8)
        case .connecting?, nil:
            ProgressView().controlSize(.mini)
        case .closed?:
            Circle().fill(Color.secondary).frame(width: 8, height: 8)
        }
    }

    private var statusText: String {
        switch connection?.state {
        case .connected?:            return "\(title) · connected"
        case .connecting?, nil:      return "Connecting to \(title)…"
        case .closed(let reason)?:   return reason
        }
    }
}

/// Shown instead of a terminal until the password session (and, for servers, the 2FA
/// step-up) is in place.
struct TerminalLocked: View {
    var title: String
    var detail: String
    var buttonTitle: String
    var action: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "lock.rectangle")
        } description: {
            Text(detail)
        } actions: {
            Button(buttonTitle, action: action).buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
