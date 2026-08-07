import SwiftUI

/// Hub for everything that edits a site's configuration.
struct SiteConfigView: View {
    let site: Site

    var body: some View {
        List {
            Section("Files") {
                ForEach(OrchestratorAPI.ConfigFile.allCases) { file in
                    NavigationLink {
                        TextConfigEditorView(site: site, file: file)
                    } label: {
                        Label(file.title, systemImage: file.symbol)
                    }
                }
                NavigationLink {
                    EnvVersionsView(site: site)
                } label: {
                    Label(".env history", systemImage: "clock.arrow.circlepath")
                }
            }

            Section("Runtime") {
                NavigationLink {
                    PHPVersionView(site: site)
                } label: {
                    LabeledContent {
                        Text(site.phpVersion ?? "—")
                            .foregroundStyle(.secondary)
                    } label: {
                        Label("PHP version", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                }
                NavigationLink {
                    SSLManagementView(site: site)
                } label: {
                    LabeledContent {
                        Text(site.sslEnabled ? (site.sslDaysLeft.map { $0.daysLabel } ?? "on") : "off")
                            .foregroundStyle(site.sslEnabled ? site.sslTone.color : .secondary)
                    } label: {
                        Label("Certificate", systemImage: "lock.shield")
                    }
                }
                NavigationLink {
                    SchedulerView(site: site)
                } label: {
                    Label("Scheduler (cron)", systemImage: "calendar.badge.clock")
                }
            }

            Section("Access") {
                NavigationLink {
                    SiteSecurityView(site: site)
                } label: {
                    LabeledContent {
                        Text(site.secBasicAuth ? "basic auth" : (site.secIpMode ?? "open"))
                            .foregroundStyle(.secondary)
                    } label: {
                        Label("Security", systemImage: "lock.trianglebadge.exclamationmark")
                    }
                }
                NavigationLink {
                    StatusPageView(site: site)
                } label: {
                    LabeledContent {
                        Text(site.statusPageEnabled ? "public" : "off")
                            .foregroundStyle(.secondary)
                    } label: {
                        Label("Status page", systemImage: "globe.badge.chevron.backward")
                    }
                }
            }
        }
        .navigationTitle("Configuration")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One editor for .env, nginx and the PHP-FPM pool — they share a response shape.
struct TextConfigEditorView: View {
    let site: Site
    let file: OrchestratorAPI.ConfigFile

    @State private var original = ""
    @State private var draft = ""
    @State private var path: String?
    @State private var state: LoadState<FileContents> = .idle
    @State private var runner = ActionRunner()
    @State private var showsSaveConfirmation = false
    @FocusState private var editorFocused: Bool

    private var hasChanges: Bool { draft != original }

    var body: some View {
        Group {
            switch state {
            case .idle, .loading:
                LoadingStateView()
            case .failed(let error):
                ErrorStateView(error: error) { Task { await load() } }
            case .loaded:
                editor
            }
        }
        .navigationTitle(file.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { if state.value == nil { await load() } }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { showsSaveConfirmation = true }
                    .disabled(!hasChanges || runner.isRunning)
                    .fontWeight(.semibold)
            }
            ToolbarItem(placement: .keyboard) {
                HStack {
                    Spacer()
                    Button("Done") { editorFocused = false }
                }
            }
        }
        .confirmationDialog(
            "Save \(file.title) on \(site.domain)?",
            isPresented: $showsSaveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Save", role: .destructive) { Task { await save() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(file.restartWarning ?? "The file is written on the live server.")
        }
    }

    private var editor: some View {
        VStack(spacing: 0) {
            if let warning = file.restartWarning {
                Label(warning, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }

            ActionFeedbackView(runner: runner)
                .padding(.horizontal, 16)

            TextEditor(text: $draft)
                .font(.system(size: 12, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($editorFocused)
                .padding(.horizontal, 8)

            HStack {
                if let path {
                    Text(path)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if hasChanges {
                    Button("Revert") { draft = original }
                        .font(.caption)
                }
                Text("\(draft.split(separator: "\n").count) lines")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    private func load() async {
        state = .loading
        do {
            let contents = try await OrchestratorAPI.shared.configFile(file, siteID: site.id)
            original = contents.content
            draft = contents.content
            path = contents.path
            state = .loaded(contents)
        } catch {
            state = .failed(APIError.wrap(error))
        }
    }

    private func save() async {
        await runner.run("save", success: "\(file.title) saved.") {
            try await OrchestratorAPI.shared.saveConfigFile(file, siteID: site.id, content: draft)
        } onSuccess: {
            original = draft
        }
    }
}

struct EnvVersionsView: View {
    let site: Site

    @State private var state: LoadState<[EnvVersion]> = .idle
    @State private var runner = ActionRunner()
    @State private var previewed: EnvVersion?
    @State private var pendingRestore: EnvVersion?

    var body: some View {
        LoadStateView(
            state: state,
            emptyTitle: "No history",
            emptyMessage: "No .env version has been recorded for this site.",
            emptyIcon: "clock.arrow.circlepath",
            isEmpty: { $0.isEmpty },
            retry: { Task { await load() } }
        ) { versions in
            List {
                Section {
                    ActionFeedbackView(runner: runner)
                        .listRowBackground(Color.clear)
                }
                ForEach(versions) { version in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(version.createdAt.shortDateTimeOrDash)
                                .font(.callout.weight(.medium))
                            Spacer()
                            Text("#\(version.id)")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Text(version.authorEmail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let note = version.note, !note.isEmpty {
                            Text(note)
                                .font(.caption)
                        }
                        HStack(spacing: 16) {
                            Button("View") { Task { await preview(version) } }
                            Button("Restore") { pendingRestore = version }
                                .foregroundStyle(.orange)
                        }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .disabled(runner.isRunning)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .navigationTitle(".env history")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { if state.value == nil { await load() } }
        .sheet(item: $previewed) { version in
            NavigationStack {
                ScrollView {
                    Text(version.content ?? "—")
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
                .navigationTitle("Version #\(version.id)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { previewed = nil }
                    }
                }
            }
        }
        .confirmationDialog(
            "Restore this .env?",
            isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
            titleVisibility: .visible,
            presenting: pendingRestore
        ) { version in
            Button("Restore version #\(version.id)", role: .destructive) {
                Task { await restore(version) }
            }
            Button("Cancel", role: .cancel) { pendingRestore = nil }
        } message: { _ in
            Text("The current .env is replaced on the live server. Laravel keeps the old values until its config cache is cleared.")
        }
    }

    private func load() async {
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await OrchestratorAPI.shared.envVersions(siteID: site.id))
        } catch {
            state = .failed(APIError.wrap(error))
        }
    }

    private func preview(_ version: EnvVersion) async {
        await runner.run("view-\(version.id)") {
            let full = try await OrchestratorAPI.shared.envVersion(siteID: site.id, versionID: version.id)
            previewed = full
        }
    }

    private func restore(_ version: EnvVersion) async {
        pendingRestore = nil
        await runner.run("restore", success: "Version #\(version.id) restored.") {
            try await OrchestratorAPI.shared.restoreEnvVersion(siteID: site.id, versionID: version.id)
        } onSuccess: {
            await load()
        }
    }
}
