import SwiftUI

@MainActor
@Observable
final class ArtisanViewModel {
    let site: Site

    private(set) var commands: [ArtisanCommand] = []
    private(set) var loadError: String?
    private(set) var isLoading = false

    let stream = StreamRunner()
    let runner = ActionRunner()

    var customCommand = ""

    private let api: OrchestratorAPI

    init(site: Site, api: OrchestratorAPI = .shared) {
        self.site = site
        self.api = api
    }

    /// Commands the panel offers, bucketed by its own `group` field.
    var grouped: [(group: String, commands: [ArtisanCommand])] {
        Dictionary(grouping: commands) { $0.group ?? "Other" }
            .map { (group: $0.key, commands: $0.value.sorted { $0.cmd < $1.cmd }) }
            .sorted { $0.group < $1.group }
    }

    /// Commands that can lose data if run against production.
    static let dangerous: Set<String> = [
        "migrate:fresh", "migrate:refresh", "migrate:reset", "migrate:rollback",
        "db:wipe", "db:seed", "cache:forget", "queue:flush"
    ]

    func isDangerous(_ command: String) -> Bool {
        let root = command.split(separator: " ").first.map(String.init) ?? command
        return Self.dangerous.contains(root)
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            commands = try await api.artisanCommands(siteID: site.id)
            loadError = nil
        } catch {
            loadError = APIError.wrap(error).errorDescription
        }
    }

    func run(_ command: String) async {
        let siteID = site.id
        stream.start { [api] in api.artisanStream(siteID: siteID) }

        await runner.run("run") { [api] in
            try await api.runArtisan(siteID: siteID, command: command)
        }

        if runner.errorMessage != nil { stream.stop() }
    }
}

struct ArtisanView: View {
    @State private var model: ArtisanViewModel
    @State private var pendingCommand: String?

    init(site: Site) {
        _model = State(initialValue: ArtisanViewModel(site: site))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let error = model.loadError {
                    InlineErrorBanner(message: error)
                }

                customCard
                ActionFeedbackView(runner: model.runner)

                if model.stream.isStreaming || !model.stream.buffer.lines.isEmpty {
                    consoleCard
                }

                ForEach(model.grouped, id: \.group) { section in
                    SectionCard(section.group, systemImage: "wand.and.stars") {
                        VStack(spacing: 0) {
                            ForEach(section.commands) { command in
                                commandRow(command)
                                if command.id != section.commands.last?.id { Divider() }
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Artisan")
        .navigationBarTitleDisplayMode(.inline)
        .task { if model.commands.isEmpty { await model.load() } }
        .onDisappear { model.stream.stop() }
        .confirmationDialog(
            "Run on \(model.site.domain)?",
            isPresented: Binding(get: { pendingCommand != nil }, set: { if !$0 { pendingCommand = nil } }),
            titleVisibility: .visible
        ) {
            if let command = pendingCommand {
                Button("php artisan \(command)", role: model.isDangerous(command) ? .destructive : nil) {
                    Task { await model.run(command) }
                    pendingCommand = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingCommand = nil }
        } message: {
            if let command = pendingCommand, model.isDangerous(command) {
                Text("This command can destroy data on the live database. There is no undo.")
            } else {
                Text("Runs against the live site.")
            }
        }
    }

    private func commandRow(_ command: ArtisanCommand) -> some View {
        Button {
            pendingCommand = command.cmd
        } label: {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(command.displayName)
                            .font(.callout)
                            .foregroundStyle(.primary)
                        if model.isDangerous(command.cmd) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                    }
                    Text(command.cmd)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                    if let description = command.description {
                        Text(description)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                Image(systemName: "play.circle")
                    .foregroundStyle(.tint)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .disabled(model.stream.isStreaming || model.runner.isRunning)
    }

    private var customCard: some View {
        SectionCard("Custom command", systemImage: "terminal") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("php artisan")
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                    TextField("route:list", text: $model.customCommand)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.callout.monospaced())
                        .onSubmit { queueCustom() }
                }
                Button {
                    queueCustom()
                } label: {
                    Label("Run", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(model.customCommand.trimmingCharacters(in: .whitespaces).isEmpty
                          || model.stream.isStreaming
                          || model.runner.isRunning)
            }
        }
    }

    private var consoleCard: some View {
        SectionCard(
            "Output",
            systemImage: "text.alignleft",
            accessory: AnyView(badge)
        ) {
            LogConsoleView(lines: model.stream.buffer.lines, isStreaming: model.stream.isStreaming)
                .frame(height: 260)
        }
    }

    @ViewBuilder
    private var badge: some View {
        if let outcome = model.stream.outcome {
            StatusBadge(outcome.rawValue, tone: outcome.tone)
        } else if model.stream.isStreaming {
            StatusBadge("running", tone: .info)
        }
    }

    private func queueCustom() {
        let command = model.customCommand.trimmingCharacters(in: .whitespaces)
        guard !command.isEmpty else { return }
        pendingCommand = command
    }
}
