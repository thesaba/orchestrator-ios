import OrchestratorKit
import SwiftUI

/// A server's logs, live: the systemd journal (all or one service) or a file under
/// /var/log, the last N lines and then, with Follow on, new lines as they are written.
/// Read-only; the stream closes when the view goes away.
struct ServerLogsView: View {
    let api: OrchestratorAPI
    let serverID: Int
    var services: [String]

    @State private var query = FleetLogsQuery()
    @State private var follow = true
    @State private var runner = StreamRunner()
    @State private var problem: String?

    private static let lineCounts = [100, 200, 500, 1000, 2000]

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            ZStack(alignment: .topLeading) {
                Color.logGround
                if runner.buffer.lines.isEmpty {
                    if runner.isStreaming {
                        VStack(alignment: .leading, spacing: 9) {
                            ForEach(0..<12, id: \.self) { line in SkeletonBar(width: CGFloat([420, 260, 520, 300, 380, 220][line % 6]), height: 9) }
                        }
                        .padding(16)
                        .shimmering()
                    } else {
                        Text(runner.isFinished ? "No lines matched." : "Choose what to read and press Show.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(16)
                    }
                } else {
                    LogLinesView(lines: runner.buffer.lines, fontSize: 12, follow: follow)
                }
            }
            Divider()
            statusBar
        }
        .onAppear { start() }
        .onDisappear { runner.stop() }
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 10) {
            Picker("Source", selection: $query.source) {
                ForEach(FleetLogsQuery.Source.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .fixedSize()

            if query.source == .journal {
                HStack(spacing: 4) {
                    TextField("All services", text: $query.unit)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                        .onSubmit(start)
                    PopUpMenuButton(symbol: "chevron.down.circle", label: "Choose a service") {
                        let menu = NSMenu(title: "Services")
                        menu.addItem(ClosureMenuItem("All services") { query.unit = ""; start() })
                        if !services.isEmpty { menu.addItem(.separator()) }
                        for name in services.sorted() {
                            menu.addItem(ClosureMenuItem(name) { query.unit = name; start() })
                        }
                        return menu
                    }
                }
            } else {
                HStack(spacing: 4) {
                    TextField("/var/log/…", text: $query.path)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 240)
                        .onSubmit(start)
                    PopUpMenuButton(symbol: "chevron.down.circle", label: "Choose a log file") {
                        let menu = NSMenu(title: "Log files")
                        for path in FleetLogsQuery.commonFiles {
                            menu.addItem(ClosureMenuItem(path) { query.path = path; start() })
                        }
                        return menu
                    }
                }
            }

            Picker("Lines", selection: $query.lines) {
                ForEach(Self.lineCounts, id: \.self) { Text("\($0) lines").tag($0) }
            }
            .labelsHidden()
            .fixedSize()

            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease").foregroundStyle(.secondary)
                TextField("Only lines with…", text: $query.grep)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                    .onSubmit(start)
            }

            Toggle("Follow", isOn: $follow)
                .toggleStyle(.switch)
                .controlSize(.small)
                .help("Keep showing new lines as they are written (up to two hours)")
                .onChange(of: follow) { start() }

            Spacer(minLength: 0)

            if runner.isStreaming {
                Button {
                    runner.stop()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
            } else {
                Button {
                    start()
                } label: {
                    Label("Show", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
            }
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(runner.buffer.plainText, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .help("Copy the lines")
            .accessibilityLabel("Copy the lines")
            .disabled(runner.buffer.lines.isEmpty)
        }
        .controlSize(.small)
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Color.statusWarningText)
            } else if runner.isStreaming {
                Circle().fill(Color.statusSuccess).frame(width: 7, height: 7)
                    .symbolEffect(.pulse, options: .repeating)
                Text(follow ? "Live · new lines appear as they are written" : "Reading…")
            } else if let error = runner.streamError {
                Label(error, systemImage: "xmark.octagon.fill").foregroundStyle(Color.statusDangerText)
            } else if runner.isFinished {
                Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
                Text(follow ? "The stream ended. Press Show to start again." : "Done")
            }
            Spacer()
            Text("\(runner.buffer.lines.count) lines").monospacedDigit()
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .frame(height: 26)
    }

    // MARK: - Streaming

    private func start() {
        if let problem = query.problem {
            self.problem = problem
            return
        }
        problem = nil
        let api = self.api, serverID = self.serverID, query = self.query, follow = self.follow
        runner.start(reconnectOnDrop: false) {
            api.fleetLogStream(serverID: serverID, query: query, follow: follow)
        }
    }
}
