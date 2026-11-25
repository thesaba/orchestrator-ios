import SwiftUI
import OrchestratorKit

@MainActor
@Observable
final class DeployViewModel {
    let site: Site

    private(set) var pending: DeployPending?
    private(set) var pendingError: String?
    private(set) var isLoadingPending = false

    let stream = StreamRunner()
    let runner = ActionRunner()

    /// The API calls this `ref` — it accepts a branch, a tag or a commit sha.
    var ref: String
    var skipTests = false

    private let api: OrchestratorAPI

    init(site: Site, api: OrchestratorAPI = .shared) {
        self.site = site
        self.ref = site.branch ?? "main"
        self.api = api
    }

    var canDeploy: Bool { !stream.isStreaming && !runner.isRunning }

    var upToDate: Bool { pending?.upToDate ?? false }

    func loadPending() async {
        isLoadingPending = true
        defer { isLoadingPending = false }
        do {
            pending = try await api.deployPending(siteID: site.id)
            pendingError = nil
        } catch {
            pendingError = APIError.wrap(error).errorDescription
        }
    }

    /// Attaches to the log stream first, then posts. The server replays its buffer on
    /// attach, so nothing is lost by ordering it this way — and if the POST fails we are
    /// already showing whatever the server has to say.
    func deploy() async {
        let siteID = site.id
        stream.start { [api] in api.deployStream(siteID: siteID) }

        await runner.run("deploy") { [self] in
            try await api.startDeploy(
                siteID: siteID,
                ref: ref.trimmingCharacters(in: .whitespaces).isEmpty ? nil : ref,
                skipTests: skipTests
            )
        }

        if runner.errorMessage != nil {
            stream.stop()
        }
    }

    func cancel() async {
        await runner.run("cancel", success: "Cancellation requested.") { [self] in
            try await api.cancelDeploy(siteID: site.id)
        }
    }

    func attachToRunningDeploy() {
        let siteID = site.id
        stream.start { [api] in api.deployStream(siteID: siteID) }
    }
}

struct DeployView: View {
    @State private var model: DeployViewModel
    @State private var showsConfirmation = false
    @Environment(\.dismiss) private var dismiss

    init(site: Site) {
        _model = State(initialValue: DeployViewModel(site: site))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    targetCard
                    if !model.stream.isStreaming && model.stream.outcome == nil {
                        optionsCard
                    }
                    ActionFeedbackView(runner: model.runner)
                    if model.stream.isStreaming || model.stream.outcome != nil || !model.stream.buffer.lines.isEmpty {
                        consoleCard
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Deploy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(model.stream.isStreaming ? "Hide" : "Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if model.stream.isStreaming {
                        Button("Cancel deploy", role: .destructive) {
                            Task { await model.cancel() }
                        }
                        .disabled(model.runner.isRunning("cancel"))
                    } else {
                        Button("Deploy") { showsConfirmation = true }
                            .disabled(!model.canDeploy)
                    }
                }
            }
            .task {
                await model.loadPending()
                if model.site.deployQueued { model.attachToRunningDeploy() }
            }
            .onDisappear { model.stream.stop() }
            .confirmationDialog(
                "Deploy to \(model.site.domain)?",
                isPresented: $showsConfirmation,
                titleVisibility: .visible
            ) {
                Button("Deploy \(model.ref)", role: .destructive) {
                    Task { await model.deploy() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(model.upToDate
                     ? "This site is already at the latest commit. Deploying will rebuild it anyway."
                     : "This runs the full deploy pipeline on the live site.")
            }
        }
    }

    private var targetCard: some View {
        SectionCard(model.site.domain, systemImage: "globe") {
            if model.isLoadingPending {
                HStack { ProgressView().controlSize(.small); Text("Checking the remote…").foregroundStyle(.secondary) }
                    .font(.footnote)
            } else if let error = model.pendingError {
                InlineErrorBanner(message: error)
            } else if let pending = model.pending {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        StatusBadge(
                            pending.upToDate ? "up to date" : "behind",
                            tone: pending.upToDate ? .good : .info
                        )
                        Spacer()
                        Text(pending.branch ?? model.ref)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    DetailRow(label: "Deployed", value: pending.shortCurrent, monospaced: true)
                    DetailRow(label: "Remote", value: pending.shortRemote, monospaced: true)

                    if !pending.commits.isEmpty {
                        Divider()
                        Text("\(pending.commits.count) commit\(pending.commits.count == 1 ? "" : "s") to deploy")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(Array(pending.commits.enumerated()), id: \.offset) { _, commit in
                            HStack(alignment: .top, spacing: 8) {
                                Text(commit.shortHash)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                Text(commit.message ?? "—")
                                    .font(.caption)
                                    .lineLimit(2)
                                Spacer()
                            }
                        }
                    }
                }
            }
        }
    }

    private var optionsCard: some View {
        SectionCard("Options", systemImage: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ref")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("main", text: $model.ref)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.callout.monospaced())
                    Text("Branch, tag or commit sha. Sent as ?ref=.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if model.site.runTests {
                    Toggle("Skip tests", isOn: $model.skipTests)
                        .font(.callout)
                }
                if model.site.runTests {
                    Label(
                        "Tests run before release · \(model.site.testFailureMode == "block" ? "failure blocks the deploy" : "failure only warns")",
                        systemImage: "checkmark.diamond"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var consoleCard: some View {
        SectionCard(
            "Output",
            systemImage: "terminal",
            accessory: AnyView(streamBadge)
        ) {
            VStack(spacing: 10) {
                LogConsoleView(lines: model.stream.buffer.lines, isStreaming: model.stream.isStreaming)
                    .frame(height: 320)

                if let error = model.stream.streamError {
                    InlineErrorBanner(message: error)
                }

                HStack {
                    if !model.stream.isStreaming, model.stream.outcome != nil {
                        Button {
                            model.stream.reattach()
                        } label: {
                            Label("Reattach", systemImage: "arrow.clockwise")
                        }
                        .font(.footnote)
                    }
                    Spacer()
                    ShareLink(item: model.stream.buffer.plainText) {
                        Label("Share log", systemImage: "square.and.arrow.up")
                    }
                    .font(.footnote)
                }
            }
        }
    }

    @ViewBuilder
    private var streamBadge: some View {
        if let outcome = model.stream.outcome {
            StatusBadge(outcome.rawValue, tone: outcome.tone)
        } else if model.stream.isStreaming {
            StatusBadge("running", tone: .info)
        }
    }
}
