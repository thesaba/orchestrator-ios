import SwiftUI

struct SystemControlView: View {
    @State private var info: SystemInfo?
    @State private var stream = StreamRunner()
    @State private var runningOperation: SystemOperation?
    @State private var pending: SystemOperation?
    @State private var ruleText = ""
    @State private var ruleProtocol = ""

    private var rule: String {
        let base = ruleText.trimmingCharacters(in: .whitespaces)
        return ruleProtocol.isEmpty ? base : "\(base)/\(ruleProtocol)"
    }

    private var isRuleValid: Bool { SystemOperation.isValidRule(ruleText) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                systemCard
                ForEach(groups, id: \.name) { group in
                    operationsCard(group.name, group.operations)
                }
                firewallRuleCard
                if stream.isStreaming || !stream.buffer.lines.isEmpty { outputCard }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("System control")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .onDisappear { stream.stop() }
        .confirmationDialog(
            pending?.title ?? "",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            titleVisibility: .visible,
            presenting: pending
        ) { operation in
            Button(operation.title, role: .destructive) {
                let op = operation
                pending = nil
                run(op)
            }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: { operation in
            Text(operation.confirmation ?? "Runs on the server that hosts every site.")
        }
    }

    private var groups: [(name: String, operations: [SystemOperation])] {
        Dictionary(grouping: SystemOperation.catalogue, by: \.group)
            .map { (name: $0.key, operations: $0.value) }
            .sorted { $0.name < $1.name }
    }

    private var systemCard: some View {
        SectionCard("Server", systemImage: "desktopcomputer") {
            if let info {
                VStack(alignment: .leading, spacing: 8) {
                    if info.rebootRequired {
                        Label("A reboot is required to finish applying updates.", systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                    DetailRow(label: "Host", value: info.hostname, monospaced: true)
                    DetailRow(label: "OS", value: info.os)
                    DetailRow(label: "Kernel", value: info.kernel, monospaced: true)
                    DetailRow(label: "Uptime", value: Durations.uptime(info.uptimeSeconds))
                    HStack {
                        Text("Updates").foregroundStyle(.secondary)
                        Spacer()
                        if let pending = info.pendingUpdates, pending >= 0 {
                            StatusBadge(pending > 0 ? "\(pending) pending" : "up to date",
                                        tone: pending > 0 ? .warning : .good, showsSymbol: false)
                        } else {
                            Text("unknown").foregroundStyle(.secondary)
                        }
                    }
                    .font(.callout)
                    HStack {
                        Text("Firewall").foregroundStyle(.secondary)
                        Spacer()
                        StatusBadge(status: info.ufwStatus)
                    }
                    .font(.callout)
                }
            } else {
                ProgressView()
            }
        }
    }

    private func operationsCard(_ title: String, _ operations: [SystemOperation]) -> some View {
        SectionCard(title, systemImage: title == "Firewall" ? "shield" : "shippingbox") {
            VStack(spacing: 0) {
                ForEach(operations) { operation in
                    Button {
                        if operation.confirmation != nil { pending = operation } else { run(operation) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(operation.title)
                                    .foregroundStyle(.primary)
                                Text(operation.subtitle)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if runningOperation?.id == operation.id && stream.isStreaming {
                                ProgressView().controlSize(.small)
                            } else if operation.confirmation != nil {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .font(.callout)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(stream.isStreaming)
                    if operation.id != operations.last?.id { Divider() }
                }
            }
        }
    }

    private var firewallRuleCard: some View {
        SectionCard("Firewall rule", systemImage: "shield.lefthalf.filled") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    TextField("8080 or ssh", text: $ruleText)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Picker("Protocol", selection: $ruleProtocol) {
                        Text("any").tag("")
                        Text("tcp").tag("tcp")
                        Text("udp").tag("udp")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                }

                HStack(spacing: 10) {
                    Button {
                        run(SystemOperation.ufwAllow(rule))
                    } label: {
                        Label("Allow", systemImage: "checkmark.shield").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        pending = SystemOperation.ufwDeny(rule)
                    } label: {
                        Label("Deny", systemImage: "xmark.shield").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .font(.footnote)
                .disabled(!isRuleValid || stream.isStreaming)

                Text("Must be a port number or one of ssh / http / https / ftp / smtp.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var outputCard: some View {
        SectionCard(
            "Output — \(runningOperation?.subtitle ?? "")",
            systemImage: "terminal",
            accessory: AnyView(badge)
        ) {
            LogConsoleView(lines: stream.buffer.lines, isStreaming: stream.isStreaming)
                .frame(height: 280)
        }
    }

    @ViewBuilder
    private var badge: some View {
        if let outcome = stream.outcome {
            StatusBadge(outcome.rawValue, tone: outcome.tone)
        } else if stream.isStreaming {
            StatusBadge("running", tone: .info)
        }
    }

    private func run(_ operation: SystemOperation) {
        runningOperation = operation
        stream.start { OrchestratorAPI.shared.systemOperationStream(operation) }
    }

    private func load() async {
        info = try? await OrchestratorAPI.shared.systemInfo()
    }
}

struct ServicesView: View {
    @State private var state: LoadState<[ServiceStatus]> = .idle
    @State private var runner = ActionRunner()
    @State private var pending: (service: ServiceStatus, action: OrchestratorAPI.ServiceAction)?

    var body: some View {
        LoadStateView(
            state: state,
            emptyTitle: "No services",
            emptyMessage: nil,
            emptyIcon: "square.stack.3d.up",
            isEmpty: { $0.isEmpty },
            retry: { Task { await load() } }
        ) { services in
            List {
                Section {
                    ActionFeedbackView(runner: runner)
                        .listRowBackground(Color.clear)
                } footer: {
                    Text("Stopping nginx, MySQL or PHP-FPM takes every site offline immediately.")
                }

                ForEach(services) { service in
                    HStack {
                        StatusDot(tone: service.tone)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(service.name)
                                .font(.callout)
                            Text(service.key)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Menu {
                            ForEach(OrchestratorAPI.ServiceAction.allCases) { action in
                                Button(action.title, role: action.isDestructive ? .destructive : nil) {
                                    pending = (service, action)
                                }
                            }
                        } label: {
                            Text(service.status)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(service.tone.color)
                        }
                        .disabled(runner.isRunning)
                    }
                }
            }
        }
        .navigationTitle("Services")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { if state.value == nil { await load() } }
        .confirmationDialog(
            pending.map { "\($0.action.title) \($0.service.name)?" } ?? "",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            titleVisibility: .visible
        ) {
            if let pending {
                Button("\(pending.action.title) \(pending.service.name)",
                       role: pending.action.isDestructive ? .destructive : nil) {
                    let target = pending
                    self.pending = nil
                    Task { await control(target.service, action: target.action) }
                }
            }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: {
            if pending?.action == .stop {
                Text("Anything depending on this service stops working until it is started again.")
            } else {
                Text("Runs systemctl on the live server.")
            }
        }
    }

    private func load() async {
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await OrchestratorAPI.shared.services())
        } catch {
            state = .failed(APIError.wrap(error))
        }
    }

    private func control(_ service: ServiceStatus, action: OrchestratorAPI.ServiceAction) async {
        await runner.run("control", success: "\(action.title) sent to \(service.name).") {
            try await OrchestratorAPI.shared.controlService(key: service.key, action: action)
        } onSuccess: {
            try? await Task.sleep(for: .seconds(1))
            await load()
        }
    }
}
