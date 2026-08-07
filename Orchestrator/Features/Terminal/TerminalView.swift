import SwiftUI

struct TerminalView: View {
    let site: Site

    @State private var client = TerminalClient()
    @State private var command = ""
    @State private var history: [String] = []
    @State private var historyIndex: Int?
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            statusBar

            LogConsoleView(lines: client.buffer.lines, isStreaming: client.isConnected)
                .padding(.horizontal, 12)

            inputBar
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Terminal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if client.isConnected {
                    Button("Disconnect", role: .destructive) { client.disconnect() }
                        .font(.footnote)
                } else {
                    Button("Connect") { client.connect(siteID: site.id) }
                        .font(.footnote)
                }
            }
        }
        .onDisappear { client.disconnect() }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            StatusDot(tone: statusTone)
            Text(statusText)
                .font(.caption)
            Spacer()
            Text(site.rootPath ?? site.domain)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var statusTone: StatusTone {
        switch client.state {
        case .connected:  return .good
        case .connecting: return .info
        case .closed(let error): return error == nil ? .neutral : .critical
        case .idle:       return .neutral
        }
    }

    private var statusText: String {
        switch client.state {
        case .idle:       return "Not connected"
        case .connecting: return "Connecting…"
        case .connected:  return "Connected as the site's user"
        case .closed(let error): return error ?? "Disconnected"
        }
    }

    private var inputBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Text("$")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.secondary)

                TextField("command", text: $command)
                    .font(.system(size: 13, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.send)
                    .focused($inputFocused)
                    .onSubmit(send)
                    .disabled(!client.isConnected)

                if client.isConnected {
                    Button {
                        client.sendInterrupt()
                    } label: {
                        Text("^C")
                            .font(.caption.monospaced())
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3)
                }
                .disabled(!client.isConnected || command.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if !history.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(history.suffix(8).reversed().enumerated()), id: \.offset) { _, item in
                            Button {
                                command = item
                                inputFocused = true
                            } label: {
                                Text(item)
                                    .font(.caption2.monospaced())
                                    .lineLimit(1)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color(.tertiarySystemFill), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Text("Line-oriented console — full-screen programs like vim or htop will not render here.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func send() {
        let text = command.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, client.isConnected else { return }
        client.send(text)
        if history.last != text { history.append(text) }
        command = ""
        historyIndex = nil
    }
}
