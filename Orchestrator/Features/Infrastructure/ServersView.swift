import SwiftUI
import OrchestratorKit

struct ServersView: View {
    @State private var state: LoadState<[ManagedServer]> = .idle

    var body: some View {
        LoadStateView(
            state: state,
            emptyTitle: "No servers",
            emptyMessage: "Add a server to deploy sites onto it.",
            emptyIcon: "server.rack",
            isEmpty: { $0.isEmpty },
            retry: { Task { await load() } }
        ) { servers in
            List(servers) { server in
                NavigationLink {
                    ServerDetailView(server: server)
                } label: {
                    HStack {
                        StatusDot(tone: server.tone)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(server.name)
                                    .font(.callout.weight(.medium))
                                if server.isLocal {
                                    Text("local")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text(server.isLocal ? "this machine" : server.address)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(server.siteCount ?? 0) sites")
                                .font(.caption)
                            if !server.scriptsSynced {
                                Text("not prepared")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Servers")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { if state.value == nil { await load() } }
    }

    private func load() async {
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await OrchestratorAPI.shared.servers())
        } catch {
            state = .failed(APIError.wrap(error))
        }
    }
}

struct ServerDetailView: View {
    let server: ManagedServer

    @State private var health: ServerHealth?
    @State private var runner = ActionRunner()
    @State private var stream = StreamRunner()
    @State private var confirmPrepare = false
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ActionFeedbackView(runner: runner)

                SectionCard(server.name, systemImage: "server.rack",
                            accessory: AnyView(StatusBadge(status: server.status, tone: server.tone))) {
                    VStack(alignment: .leading, spacing: 8) {
                        DetailRow(label: "Kind", value: server.kind)
                        DetailRow(label: "Address", value: server.isLocal ? "—" : server.address, monospaced: true)
                        DetailRow(label: "SSH key", value: server.hasKey ? (server.sshKeyFingerprint ?? "present") : "none", monospaced: server.hasKey)
                        DetailRow(label: "Sites", value: "\(server.siteCount ?? 0)")
                        DetailRow(label: "Last seen", value: server.lastSeenAt.relativeShortOrDash)
                        HStack {
                            Text("Scripts").foregroundStyle(.secondary)
                            Spacer()
                            StatusBadge(server.scriptsSynced ? "synced" : "not prepared",
                                        tone: server.scriptsSynced ? .good : .warning)
                        }
                        .font(.callout)
                        if let notes = server.notes, !notes.isEmpty {
                            DetailRow(label: "Notes", value: notes)
                        }
                    }
                }

                if let health {
                    SectionCard("Health", systemImage: "stethoscope") {
                        VStack(alignment: .leading, spacing: 8) {
                            if let ok = health.ok {
                                HStack {
                                    Text("Reachable").foregroundStyle(.secondary)
                                    Spacer()
                                    StatusBadge(ok ? "yes" : "no", tone: ok ? .good : .critical)
                                }
                                .font(.callout)
                            }
                            if let message = health.message {
                                Text(message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            DisclosureGroup("Raw response") {
                                Text(health.raw.prettyPrinted)
                                    .font(.caption2.monospaced())
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .font(.caption)
                        }
                    }
                }

                SectionCard("Actions", systemImage: "bolt") {
                    VStack(spacing: 10) {
                        Button {
                            Task { await test() }
                        } label: {
                            Label("Test connection", systemImage: "antenna.radiowaves.left.and.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            confirmPrepare = true
                        } label: {
                            Label(server.scriptsSynced ? "Re-run preparation" : "Prepare server",
                                  systemImage: "wrench.and.screwdriver")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        if (server.siteCount ?? 0) == 0 && !server.isLocal {
                            Button(role: .destructive) {
                                confirmDelete = true
                            } label: {
                                Label("Remove server", systemImage: "trash").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .disabled(runner.isRunning || stream.isStreaming)
                }

                if stream.isStreaming || !stream.buffer.lines.isEmpty {
                    SectionCard("Preparation log", systemImage: "terminal") {
                        LogConsoleView(lines: stream.buffer.lines, isStreaming: stream.isStreaming)
                            .frame(height: 300)
                    }
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(server.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { health = try? await OrchestratorAPI.shared.serverHealth(id: server.id) }
        .onDisappear { stream.stop() }
        .confirmationDialog("Prepare \(server.name)?", isPresented: $confirmPrepare, titleVisibility: .visible) {
            Button("Prepare", role: .destructive) { Task { await prepare() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Installs and updates the panel's helper scripts over SSH. Safe to re-run, but it does touch a machine that is serving live sites.")
        }
        .confirmationDialog("Remove \(server.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { Task { await remove() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The server is removed from the panel. Nothing on the machine itself is deleted.")
        }
    }

    private func test() async {
        await runner.run("test", success: "Connection OK.") {
            try await OrchestratorAPI.shared.testServer(id: server.id)
        } onSuccess: {
            health = try? await OrchestratorAPI.shared.serverHealth(id: server.id)
        }
    }

    private func prepare() async {
        let id = server.id
        stream.start { OrchestratorAPI.shared.serverPrepareStream(id: id) }
        await runner.run("prepare", success: "Preparation started.") {
            try await OrchestratorAPI.shared.prepareServer(id: id)
        }
        if runner.errorMessage != nil { stream.stop() }
    }

    private func remove() async {
        await runner.run("remove", success: "Server removed.") {
            try await OrchestratorAPI.shared.deleteServer(id: server.id)
        }
    }
}

// MARK: - DigitalOcean

@MainActor
@Observable
final class DropletViewModel {
    private(set) var status: DropletStatus?
    private(set) var sizes: [DropletSize] = []
    private(set) var actions: [DropletAction] = []
    private(set) var snapshots: [DropletSnapshot] = []
    private(set) var backups: [DropletSnapshot] = []
    private(set) var loadError: APIError?

    var hasLoadedOnce = false
    let runner = ActionRunner()

    var droplet: Droplet? { status?.droplet }

    func load() async {
        defer { hasLoadedOnce = true }
        do {
            status = try await OrchestratorAPI.shared.dropletStatus()
            loadError = nil
        } catch {
            loadError = APIError.wrap(error)
        }
        sizes = (try? await OrchestratorAPI.shared.dropletSizes()) ?? []
        actions = (try? await OrchestratorAPI.shared.dropletActions()) ?? []
        snapshots = (try? await OrchestratorAPI.shared.snapshots()) ?? []
        backups = (try? await OrchestratorAPI.shared.dropletBackups()) ?? []
    }

    func perform(_ type: OrchestratorAPI.DropletActionType) async {
        await runner.run(type.rawValue, success: "\(type.title) requested.") {
            try await OrchestratorAPI.shared.performDropletAction(type)
        } onSuccess: { [self] in
            try? await Task.sleep(for: .seconds(2))
            await load()
        }
    }

    func createSnapshot(named name: String) async {
        await runner.run("snapshot", success: "Snapshot started. DigitalOcean takes a few minutes.") {
            try await OrchestratorAPI.shared.createSnapshot(named: name)
        } onSuccess: { [self] in await load() }
    }

    func deleteSnapshot(_ snapshot: DropletSnapshot) async {
        await runner.run("delete-\(snapshot.id)", success: "Snapshot deleted.") {
            try await OrchestratorAPI.shared.deleteSnapshot(id: snapshot.id)
        } onSuccess: { [self] in await load() }
    }

    func rename(to name: String) async {
        await runner.run("rename", success: "Droplet renamed.") {
            try await OrchestratorAPI.shared.renameDroplet(to: name)
        } onSuccess: { [self] in await load() }
    }

    func resize(to slug: String, disk: Bool) async {
        await runner.run("resize", success: "Resize started. The droplet reboots as part of it.") {
            try await OrchestratorAPI.shared.resizeDroplet(to: slug, resizeDisk: disk)
        } onSuccess: { [self] in await load() }
    }
}

struct DropletControlView: View {
    @State private var model = DropletViewModel()
    @State private var pendingAction: OrchestratorAPI.DropletActionType?
    @State private var snapshotName = ""
    @State private var showsSnapshotPrompt = false
    @State private var showsRenamePrompt = false
    @State private var newName = ""

    var body: some View {
        Group {
            if !model.hasLoadedOnce {
                LoadingStateView()
            } else if let error = model.loadError, model.droplet == nil {
                ErrorStateView(error: error) { Task { await model.load() } }
            } else if model.status?.configured != true {
                EmptyStateView(
                    icon: "drop",
                    title: "DigitalOcean not configured",
                    message: "Add a DigitalOcean API token in the panel's settings to control the droplet from here."
                )
            } else {
                content
            }
        }
        .navigationTitle("DigitalOcean")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.load() }
        .task { if !model.hasLoadedOnce { await model.load() } }
        .confirmationDialog(
            "\(pendingAction?.title ?? "") the droplet?",
            isPresented: Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } }),
            titleVisibility: .visible,
            presenting: pendingAction
        ) { action in
            Button(action.title, role: action.isDestructive ? .destructive : nil) {
                let type = action
                pendingAction = nil
                Task { await model.perform(type) }
            }
            Button("Cancel", role: .cancel) { pendingAction = nil }
        } message: { action in
            Text(action.warning)
        }
        .alert("New snapshot", isPresented: $showsSnapshotPrompt) {
            TextField("Name", text: $snapshotName)
            Button("Create") {
                let name = snapshotName.trimmingCharacters(in: .whitespaces)
                snapshotName = ""
                guard !name.isEmpty else { return }
                Task { await model.createSnapshot(named: name) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Taking a snapshot can pause the droplet briefly and DigitalOcean charges for stored snapshots.")
        }
        .alert("Rename droplet", isPresented: $showsRenamePrompt) {
            TextField("Name", text: $newName)
            Button("Rename") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                Task { await model.rename(to: name) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 14) {
                ActionFeedbackView(runner: model.runner)
                if let droplet = model.droplet { dropletCard(droplet) }
                powerCard
                snapshotsCard
                if !model.backups.isEmpty { backupsCard }
                if !model.actions.isEmpty { actionsCard }
                if !model.sizes.isEmpty { resizeCard }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
    }

    private func dropletCard(_ droplet: Droplet) -> some View {
        SectionCard(droplet.name, systemImage: "drop.fill",
                    accessory: AnyView(StatusBadge(status: droplet.status, tone: droplet.tone))) {
            VStack(alignment: .leading, spacing: 8) {
                DetailRow(label: "Specs", value: droplet.specs)
                DetailRow(label: "Public IP", value: droplet.publicIPv4, monospaced: true)
                DetailRow(label: "Region", value: droplet.region?.name)
                DetailRow(label: "Image", value: [droplet.image?.distribution, droplet.image?.name].compactMap { $0 }.joined(separator: " "))
                DetailRow(label: "Size", value: droplet.sizeSlug, monospaced: true)
                DetailRow(label: "Price", value: droplet.size?.priceMonthly.map { String(format: "$%.0f/mo", $0) })
                DetailRow(label: "Created", value: droplet.createdAt.shortDateTimeOrDash)
                if droplet.locked {
                    Label("Locked — an action is in progress", systemImage: "lock")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var powerCard: some View {
        SectionCard("Power", systemImage: "power") {
            VStack(spacing: 10) {
                ForEach(OrchestratorAPI.DropletActionType.allCases) { action in
                    Button(role: action.isDestructive ? .destructive : nil) {
                        pendingAction = action
                    } label: {
                        HStack {
                            Text(action.title)
                            Spacer()
                            if model.runner.isRunning(action.rawValue) {
                                ProgressView().controlSize(.small)
                            }
                        }
                    }
                    .disabled(model.runner.isRunning || model.droplet?.locked == true)
                    if action != OrchestratorAPI.DropletActionType.allCases.last { Divider() }
                }
            }
            .font(.callout)
        }
    }

    private var snapshotsCard: some View {
        SectionCard(
            "Snapshots",
            systemImage: "camera",
            accessory: AnyView(
                Button("New") { showsSnapshotPrompt = true }
                    .font(.footnote)
                    .disabled(model.runner.isRunning)
            )
        ) {
            if model.snapshots.isEmpty {
                Text("No snapshots.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(model.snapshots) { snapshot in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(snapshot.name)
                                    .font(.callout)
                                    .lineLimit(1)
                                Text("\(snapshot.sizeLabel) · \(snapshot.createdAt.relativeShortOrDash)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Delete", role: .destructive) {
                                Task { await model.deleteSnapshot(snapshot) }
                            }
                            .font(.caption)
                            .buttonStyle(.plain)
                            .disabled(model.runner.isRunning)
                        }
                    }
                }
            }
        }
    }

    private var backupsCard: some View {
        SectionCard("Backups", systemImage: "clock.arrow.circlepath") {
            VStack(spacing: 8) {
                ForEach(model.backups) { backup in
                    HStack {
                        Text(backup.name)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Text(backup.createdAt.relativeShortOrDash)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var actionsCard: some View {
        SectionCard("Recent actions", systemImage: "clock") {
            VStack(spacing: 8) {
                ForEach(model.actions.prefix(8)) { action in
                    HStack {
                        StatusDot(tone: action.tone)
                        Text(action.type.replacingOccurrences(of: "_", with: " "))
                            .font(.caption)
                        Spacer()
                        Text(action.completedAt?.relativeShort ?? action.startedAt.relativeShortOrDash)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var resizeCard: some View {
        SectionCard("Resize", systemImage: "arrow.up.left.and.arrow.down.right") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Resizing reboots the droplet. Growing the disk is permanent — you cannot shrink it afterwards.")
                    .font(.caption)
                    .foregroundStyle(.orange)

                NavigationLink {
                    ResizePickerView(model: model)
                } label: {
                    HStack {
                        Text("Choose a size")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .font(.callout)
                }

                Button("Rename droplet") { newName = model.droplet?.name ?? ""; showsRenamePrompt = true }
                    .font(.callout)
                    .disabled(model.runner.isRunning)
            }
        }
    }
}

struct ResizePickerView: View {
    let model: DropletViewModel

    @State private var selected: DropletSize?
    @State private var resizeDisk = false
    @State private var showsConfirmation = false

    var body: some View {
        List {
            Section {
                Toggle("Also grow the disk", isOn: $resizeDisk)
            } footer: {
                Text(resizeDisk
                     ? "Permanent. The droplet can never be resized back down afterwards."
                     : "CPU and RAM only — reversible.")
                .foregroundStyle(resizeDisk ? .orange : .secondary)
            }

            Section("Available sizes") {
                ForEach(model.sizes.filter(\.available)) { size in
                    Button {
                        selected = size
                        showsConfirmation = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(size.slug)
                                    .font(.callout.monospaced())
                                    .foregroundStyle(.primary)
                                Text(size.summary)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if size.slug == model.droplet?.sizeSlug {
                                StatusBadge("current", tone: .good, showsSymbol: false)
                            } else {
                                Text(size.priceLabel)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(size.slug == model.droplet?.sizeSlug || model.runner.isRunning)
                }
            }
        }
        .navigationTitle("Resize")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Resize to \(selected?.slug ?? "")?",
            isPresented: $showsConfirmation,
            titleVisibility: .visible
        ) {
            Button("Resize", role: .destructive) {
                guard let slug = selected?.slug else { return }
                Task { await model.resize(to: slug, disk: resizeDisk) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(resizeDisk
                 ? "The droplet powers off, resizes and reboots. Growing the disk cannot be undone."
                 : "The droplet powers off, resizes and reboots. Every site is offline for a few minutes.")
        }
    }
}
