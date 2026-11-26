import OrchestratorKit
import SwiftUI

/// Runs a saved script or a one-off command on chosen servers and shows each server's
/// output as it comes in. Needs the password session with a 2FA step-up, and the "free
/// commands" switch on each server — the same rules as the panel.
struct FleetRunSheet: View {
    let environment: AppEnvironment
    var servers: [FleetServer]

    enum Mode: String, CaseIterable, Identifiable {
        case script = "Saved script", command = "Command"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .script
    @State private var scripts: [FleetScript] = []
    @State private var scriptID: Int?
    @State private var command = ""
    @State private var timeout = 300
    @State private var selected: Set<Int> = []
    @State private var loadError: String?

    @State private var run: FleetRun?
    @State private var runError: String?
    @State private var isStarting = false
    @State private var expanded: Set<Int> = []
    @Environment(\.dismiss) private var dismiss

    private var admin: AdminAccess { environment.admin }
    private var script: FleetScript? { scripts.first { $0.id == scriptID } }

    private var task: FleetRunTask? {
        switch mode {
        case .script:  return script.map(FleetRunTask.script)
        case .command: return .command(command, timeoutSeconds: timeout)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                IconBadge(symbol: "terminal.fill", tint: Vivid.indigo, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Run on servers").font(.system(size: 17, weight: .semibold))
                    Text(admin.isElevated() ? "2FA confirmed · unlocked for this session" : "Needs your password and a 2FA code")
                        .font(.system(size: 12))
                        .foregroundStyle(admin.isElevated() ? Color.statusSuccessText : .secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if let run {
                results(run)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    whatToRun.frame(maxWidth: .infinity, alignment: .topLeading)
                    serverPicker.frame(width: 300, alignment: .topLeading)
                }
                footer
            }
        }
        .padding(20)
        .frame(minWidth: 860, idealWidth: 940, minHeight: 560, idealHeight: 640)
        .task { await loadScripts() }
    }

    // MARK: - Choosing

    private var whatToRun: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Run", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            if mode == .script {
                if let loadError {
                    Label(loadError, systemImage: "exclamationmark.triangle").foregroundStyle(Color.statusWarningText).font(.system(size: 12))
                } else if scripts.isEmpty {
                    Text("No saved scripts. Add them in the web panel under Servers → Scripts.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                List(scripts, selection: $scriptID) { script in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(script.name).font(.system(size: 13, weight: .medium))
                        if let description = script.description, !description.isEmpty {
                            Text(description).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .tag(script.id)
                }
                .listStyle(.inset)
                .frame(height: 170)
                if let script {
                    ScrollView {
                        Text(script.body)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(10)
                    }
                    .background(Color.logGround)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .frame(maxHeight: .infinity)
                }
            } else {
                TextEditor(text: $command)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .background(Color.logGround)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .frame(minHeight: 200, maxHeight: .infinity)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Command")
                Stepper("Timeout: \(timeout) s", value: $timeout, in: 10...3600, step: 30)
                    .font(.system(size: 12))
            }
        }
    }

    private var serverPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionHeader(title: "Servers", symbol: "server.rack", tint: Vivid.teal)
                Spacer()
                Button("All") { selected = Set(servers.filter(\.commandsEnabled).map(\.id)) }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(servers) { server in
                        Toggle(isOn: Binding(get: { selected.contains(server.id) },
                                             set: { on in if on { selected.insert(server.id) } else { selected.remove(server.id) } })) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(server.name).font(.system(size: 12, weight: .medium))
                                Text(server.commandsEnabled ? (server.location ?? server.channel) : "Free commands are off for this server")
                                    .font(.system(size: 11))
                                    .foregroundStyle(server.commandsEnabled ? Color.secondary : Color.statusWarningText)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .disabled(!server.commandsEnabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
            }
            .card()
            Text("A server runs commands and scripts only when its “free commands” switch is on in the web panel.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            if let message = task?.problem(serverCount: selected.count) ?? (task == nil ? "Choose a script." : nil) {
                Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if let runError {
                Label(runError, systemImage: "xmark.octagon").font(.system(size: 12)).foregroundStyle(Color.statusDangerText)
            }
            Spacer()
            Button(isStarting ? "Starting…" : "Run…") { start() }
                .buttonStyle(.borderedProminent)
                .disabled(isStarting || task == nil || task?.problem(serverCount: selected.count) != nil)
                .keyboardShortcut(.return, modifiers: .command)
        }
    }

    // MARK: - Running

    private func loadScripts() async {
        do {
            scripts = try await environment.api.fleetScripts()
            loadError = nil
            if scriptID == nil { scriptID = scripts.first?.id }
        } catch {
            loadError = APIError.wrap(error).errorDescription
        }
    }

    private func start() {
        guard let task, task.problem(serverCount: selected.count) == nil else { return }
        let targets = servers.filter { selected.contains($0.id) }
        let names = targets.map(\.name)
        let preview = task.shellText.split(separator: "\n").prefix(4).joined(separator: "\n")
        isStarting = true
        runError = nil
        Task {
            defer { isStarting = false }
            let confirmation = Confirmation(
                title: "Run “\(task.title)” on \(names.count == 1 ? names[0] : "\(names.count) servers")?",
                consequence: "Runs as the servers’ login user on \(names.joined(separator: ", ")):\n\n\(preview)\(task.shellText.split(separator: "\n").count > 4 ? "\n…" : "")\n\n"
                    + "It runs on the live servers right away and can change or delete anything that user can.",
                confirmTitle: "Run", isDestructive: true)
            guard AlertPresenter.confirm(confirmation) else { return }
            guard await AdminPrompt.ensureElevated(admin, suggestedEmail: environment.session.user?.email),
                  let api = admin.api else { return }
            do {
                let id = try await api.startFleetRun(task, serverIDs: targets.map(\.id))
                await follow(runID: id, api: api)
            } catch {
                runError = APIError.wrap(error).errorDescription
            }
        }
    }

    /// Reads the run (GET) every second until every server has finished.
    private func follow(runID: Int, api: OrchestratorAPI) async {
        while !Task.isCancelled {
            if let current = try? await api.fleetRun(id: runID) {
                run = current
                if current.isFinished { return }
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func results(_ run: FleetRun) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(run.command.split(separator: "\n").first.map(String.init) ?? run.command)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1)
                Spacer()
                if run.isFinished {
                    Button("Run Again…") { self.run = nil }
                } else {
                    ProgressView().controlSize(.small)
                    Button("Cancel Run") {
                        let api = admin.api
                        Task { try? await api?.cancelFleetRun(id: run.id) }
                    }
                }
            }
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(run.targets) { target in
                        TargetResult(target: target, expanded: expanded.contains(target.id)) {
                            if expanded.contains(target.id) { expanded.remove(target.id) } else { expanded.insert(target.id) }
                        }
                    }
                }
            }
        }
    }
}

private struct TargetResult: View {
    var target: FleetRun.Target
    var expanded: Bool
    var toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: toggle) {
                HStack(spacing: 10) {
                    Image(systemName: symbol).foregroundStyle(color).frame(width: 16)
                        .symbolEffect(.pulse, options: .repeating, isActive: target.status == "running")
                    Text(target.serverName ?? "Server \(target.serverId)").font(.system(size: 13, weight: .medium))
                    Text(target.status.capitalized + (target.exitCode.map { " · exit \($0)" } ?? ""))
                        .font(.system(size: 12))
                        .foregroundStyle(color)
                    Spacer()
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded || target.status == "running" {
                ScrollView {
                    Text((target.output ?? "").isEmpty ? "No output yet." : target.output ?? "")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.logText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(10)
                }
                .frame(maxHeight: 220)
                .background(Color.logGround)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(12)
        .card()
    }

    private var symbol: String {
        switch target.status {
        case "success":            return "checkmark.circle.fill"
        case "running", "pending": return "hourglass"
        case "denied":             return "hand.raised.fill"
        default:                   return "xmark.octagon.fill"
        }
    }

    private var color: Color {
        switch target.status {
        case "success":            return .statusSuccessText
        case "running", "pending": return .accentText
        default:                   return .statusDangerText
        }
    }
}
