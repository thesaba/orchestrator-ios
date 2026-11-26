import OrchestratorKit
import SwiftUI

/// The Artisan commands the panel allows, grouped, and the output of the one run here.
/// Commands run as listed (the panel accepts no extra options); each confirms first and the
/// ones that change data or stop workers also need Touch ID.
struct SiteArtisanTab: View {
    let environment: AppEnvironment
    let siteID: Int

    @State private var commands: [ArtisanCommand] = []
    @State private var selected: String?
    @State private var filter = ""
    @State private var hasLoaded = false
    /// The command run from this tab. Held here because `LogCoordinator` is not observable:
    /// the session itself is, so its lines appear as they stream in.
    @State private var session: LogSession?

    private var groups: [(name: String, commands: [ArtisanCommand])] {
        let needle = filter.trimmingCharacters(in: .whitespaces).lowercased()
        let shown = commands.filter { needle.isEmpty || $0.cmd.lowercased().contains(needle) || ($0.description ?? "").lowercased().contains(needle) }
        var order: [String] = []
        var byGroup: [String: [ArtisanCommand]] = [:]
        for command in shown {
            let group = command.group ?? "Other"
            if byGroup[group] == nil { order.append(group) }
            byGroup[group, default: []].append(command)
        }
        return order.map { ($0, byGroup[$0] ?? []) }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                TextField("Filter commands", text: $filter)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .padding(10)
                List(selection: $selected) {
                    ForEach(groups, id: \.name) { group in
                        Section(group.name) {
                            ForEach(group.commands) { command in
                                HStack {
                                    Text(command.cmd).font(.system(size: 12, design: .monospaced))
                                    Spacer()
                                    if ArtisanSafety.needsAuthentication(command.cmd) {
                                        Text("Touch ID").font(.system(size: 10)).foregroundStyle(Color.statusWarningText)
                                    }
                                }
                                .tag(command.cmd)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .overlay {
                    if commands.isEmpty {
                        if hasLoaded {
                            Text("No commands available").foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 12) { ForEach(0..<8, id: \.self) { _ in SkeletonBar(height: 10) } }
                                .padding(16)
                                .shimmering()
                                .frame(maxHeight: .infinity, alignment: .top)
                        }
                    }
                }
            }
            .frame(width: 280)
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                runCard
                output
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .task(id: siteID) {
            if let current = environment.logs.session(for: siteID), case .artisan = current.kind { session = current }
            commands = ((try? await environment.api.artisanCommands(siteID: siteID)) ?? []).sorted { $0.cmd < $1.cmd }
            hasLoaded = true
            if selected == nil { selected = commands.first { $0.cmd.hasPrefix("about") }?.cmd ?? commands.first?.cmd }
        }
    }

    private var runCard: some View {
        let command = commands.first { $0.cmd == selected }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(command.map { "php artisan \($0.cmd)" } ?? "Choose a command")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                Spacer()
                Button("Run…") {
                    guard let cmd = command?.cmd else { return }
                    let executor = environment.executor
                    let id = siteID
                    Task {
                        if let started = await executor.runArtisanInline(siteID: id, command: cmd) { session = started }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(command == nil || session?.isFinished == false)
                .keyboardShortcut(.return, modifiers: .command)
            }
            if let description = command?.description {
                Text(description).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if let cmd = command?.cmd, ArtisanSafety.isDataLoss(cmd) {
                Label("Can delete or change production data. Make sure a recent backup exists.", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.statusWarningText)
            }
        }
        .padding(14)
        .card()
    }

    @ViewBuilder
    private var output: some View {
        if let session {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    SectionHeader(title: "Output · \(session.title)", symbol: "text.alignleft", tint: Vivid.purple)
                    Spacer()
                    Text(stateText(session)).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                LogLinesView(lines: session.lines, fontSize: 12, follow: true)
                    .background(Color.logGround)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        } else {
            Text("Output of a command run here appears below it.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private func stateText(_ session: LogSession) -> String {
        switch session.state {
        case .connecting:  return "Connecting…"
        case .running:     return "Running"
        case .succeeded:   return "Finished"
        // A quick command can finish before the stream attaches: its output is replayed and
        // the panel answers "idle", without an exit status.
        case .failed:      return session.runner.lastStatus == "idle" ? "Finished" : "Failed"
        case .cancelled:   return "Cancelled"
        case .notRunning:  return "Finished"
        }
    }
}
