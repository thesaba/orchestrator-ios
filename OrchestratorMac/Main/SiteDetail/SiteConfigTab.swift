import OrchestratorKit
import SwiftUI

/// The site's `.env`: a table with secrets masked, a raw editor, the changes about to be
/// saved, and the version history with restore.
///
/// Reading is a GET; secrets show only after Touch ID; saving and restoring confirm with the
/// list of changed keys and need Touch ID.
struct SiteConfigTab: View {
    let environment: AppEnvironment
    let siteID: Int

    enum Mode: String, CaseIterable, Identifiable {
        case table = "Table", raw = "Raw file"
        var id: String { rawValue }
    }

    @State private var original: String?
    @State private var draft = ""
    @State private var path: String?
    @State private var versions: [EnvVersion] = []
    @State private var mode: Mode = .table
    @State private var secretsVisible = false
    @State private var filter = ""
    @State private var error: String?
    @State private var isSaving = false
    @State private var preview: EnvVersion?

    private var executor: CommandExecutor { environment.executor }
    private var changes: [EnvChange] { original.map { EnvChange.between($0, draft) } ?? [] }
    private var isEdited: Bool { original != nil && original != draft }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            editor
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    changesCard
                    historyCard
                }
                .padding(16)
            }
            .frame(width: 320)
        }
        .task(id: siteID) { await load() }
        .sheet(item: $preview) { version in
            EnvVersionSheet(environment: environment, siteID: siteID, version: version, current: original ?? "") {
                preview = nil
                Task { await load() }
            }
        }
    }

    // MARK: - Editor

    private var editor: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(".env").font(.system(size: 13, weight: .semibold))
                if isEdited {
                    Text(changes.count == 1 ? "1 unsaved change" : "\(changes.count) unsaved changes")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.statusWarningText)
                        .padding(.horizontal, 8)
                        .frame(height: 20)
                        .background(Capsule().fill(Color.tintWarning))
                }
                Spacer()
                Picker("View", selection: modeBinding) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Button(secretsVisible ? "Hide Secrets" : "Show Secrets…") { toggleSecrets() }
                    .help(secretsVisible ? "Mask the secret values again" : "Asks for Touch ID")
                Button("Discard") { draft = original ?? "" }
                    .disabled(!isEdited || isSaving)
                Button("Save…") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isEdited || isSaving)
            }
            .controlSize(.small)
            .padding(.horizontal, 16)
            .frame(height: 44)
            Divider()

            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Color.statusDangerText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if original == nil {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if mode == .raw {
                TextEditor(text: $draft)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .background(Color.logGround)
                    .autocorrectionDisabled()
                    .accessibilityLabel(".env contents")
            } else {
                table
            }
        }
    }

    private var table: some View {
        let file = EnvFile(draft)
        let needle = filter.trimmingCharacters(in: .whitespaces).lowercased()
        return VStack(spacing: 0) {
            TextField("Filter variables", text: $filter)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            List {
                ForEach(file.groups) { group in
                    let entries = group.entries.filter {
                        needle.isEmpty || $0.key.lowercased().contains(needle) || (!$0.isSecret && $0.value.lowercased().contains(needle))
                    }
                    if !entries.isEmpty {
                        Section(group.name) {
                            ForEach(entries) { entry in
                                EnvRow(entry: entry, secretsVisible: secretsVisible,
                                       change: changes.first { $0.key == entry.key })
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)
            if let path {
                Text(path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            }
        }
    }

    /// The raw file shows every secret, so switching to it asks for Touch ID like "Show Secrets".
    private var modeBinding: Binding<Mode> {
        Binding(get: { mode }, set: { newMode in
            guard newMode == .raw, !secretsVisible else { mode = newMode; return }
            Task {
                if await executor.authorizeRevealingSecrets(siteID: siteID) {
                    secretsVisible = true
                    mode = .raw
                }
            }
        })
    }

    private func toggleSecrets() {
        if secretsVisible {
            secretsVisible = false
            mode = .table
            return
        }
        Task { secretsVisible = await executor.authorizeRevealingSecrets(siteID: siteID) }
    }

    // MARK: - Side cards

    private var changesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Changes to save")
            VStack(alignment: .leading, spacing: 4) {
                if changes.isEmpty {
                    Text(isEdited ? "Only comments or formatting changed." : "No changes. Edit in Raw file view.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(changes) { change in
                        Text(change.summary + (change.isSecret ? "  (secret)" : ""))
                            .foregroundStyle(change.kind == .removed ? Color.statusDangerText
                                             : (change.kind == .added ? Color.statusSuccessText : Color.statusWarningText))
                    }
                }
            }
            .font(.system(size: 12, design: .monospaced))
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
            Text("Saving asks for Touch ID. Laravel keeps cached config until you run config:clear or optimize:clear.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Version history")
            if versions.isEmpty {
                EmptyRow(text: original == nil ? "Loading…" : "No saved versions", symbol: "clock.arrow.circlepath")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(versions.prefix(20).enumerated()), id: \.element.id) { index, version in
                        if index > 0 { Divider() }
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(version.note?.ifEmpty("Saved") ?? "Saved").font(.system(size: 12)).lineLimit(1)
                                Text([version.createdAt?.formatted(date: .abbreviated, time: .shortened), version.authorEmail]
                                    .compactMap { $0 }.joined(separator: " · "))
                                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Button("View") { preview = version }
                                .buttonStyle(RowButtonStyle())
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                    }
                }
                .card()
            }
        }
    }

    // MARK: - Loading and saving

    private func load() async {
        do {
            async let file = environment.api.configFile(.env, siteID: siteID)
            async let history = try? environment.api.envVersions(siteID: siteID)
            let contents = try await file
            original = contents.content
            draft = contents.content
            path = contents.path
            versions = await history ?? []
            error = nil
        } catch {
            self.error = APIError.wrap(error).errorDescription
        }
    }

    private func save() {
        guard let original else { return }
        let content = draft
        isSaving = true
        Task {
            defer { isSaving = false }
            if await executor.saveEnv(siteID: siteID, original: original, content: content) {
                await load()
            }
        }
    }
}

/// One variable: key, value (masked when secret) and how it changed.
private struct EnvRow: View {
    var entry: EnvFile.Entry
    var secretsVisible: Bool
    var change: EnvChange?

    var body: some View {
        HStack(spacing: 12) {
            Text(entry.key)
                .frame(width: 220, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(entry.isSecret && !secretsVisible ? entry.maskedValue : entry.value)
                .foregroundStyle(entry.isSecret && !secretsVisible ? .tertiary : .secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(note)
                .font(.system(size: 11))
                .foregroundStyle(change == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color.statusWarningText))
                .frame(width: 70, alignment: .trailing)
        }
        .font(.system(size: 12, design: .monospaced))
        .listRowBackground(change == nil ? Color.clear : Color.tintWarning)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.key)
        .accessibilityValue(entry.isSecret && !secretsVisible ? "Secret, hidden" : entry.value)
    }

    private var note: String {
        switch change?.kind {
        case .added?:   return "New"
        case .changed?: return "Changed"
        default:        return entry.isSecret ? "Secret" : ""
        }
    }
}

/// An older `.env` version: which keys differ from the live file, and Restore.
private struct EnvVersionSheet: View {
    let environment: AppEnvironment
    let siteID: Int
    let version: EnvVersion
    let current: String
    var onDone: () -> Void

    @State private var content: String?
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Version from \(version.createdAt?.formatted(date: .abbreviated, time: .shortened) ?? "#\(version.id)")")
                .font(.headline)
            Text("Saved by \(version.authorEmail). Compared with the live .env (keys only):")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Group {
                if let error {
                    Text(error).foregroundStyle(Color.statusDangerText)
                } else if let content {
                    let changes = EnvChange.between(current, content)
                    if changes.isEmpty {
                        Text("Same variables and values as the live file.").foregroundStyle(.secondary)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(changes) { Text($0.summary) }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 220)
                    }
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .font(.system(size: 12, design: .monospaced))
            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Restore This Version…") {
                    Task {
                        if await environment.executor.restoreEnv(siteID: siteID, version: version) { onDone() }
                    }
                }
                .disabled(content == nil)
            }
        }
        .padding(20)
        .frame(width: 460)
        .task {
            do {
                content = try await environment.api.envVersion(siteID: siteID, versionID: version.id).content ?? ""
            } catch {
                self.error = APIError.wrap(error).errorDescription
            }
        }
    }
}
