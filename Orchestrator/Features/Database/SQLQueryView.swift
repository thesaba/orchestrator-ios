import SwiftUI
import OrchestratorKit

/// A SQL console against a live production database, so the destructive path is
/// deliberately awkward: writes need a second confirmation naming the statement.
struct SQLQueryView: View {
    let site: Site
    let database: SiteDatabase

    @State private var sql = ""
    @State private var result: QueryResult?
    @State private var runner = ActionRunner()
    @State private var showsWriteConfirmation = false
    @FocusState private var editorFocused: Bool

    /// Statements that only read. Anything else is treated as dangerous.
    private static let readOnlyPrefixes = ["select", "show", "describe", "desc", "explain", "with"]

    private var trimmed: String {
        sql.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isReadOnly: Bool {
        let first = trimmed.lowercased().split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
        return Self.readOnlyPrefixes.contains(first)
    }

    private var statementKind: String {
        trimmed.split(whereSeparator: { $0.isWhitespace }).first.map { $0.uppercased() } ?? "statement"
    }

    var body: some View {
        VStack(spacing: 0) {
            editor
            Divider()
            resultArea
        }
        .navigationTitle(database.dbName)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Run a \(statementKind) on the live database?",
            isPresented: $showsWriteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Run \(statementKind)", role: .destructive) { Task { await run() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This is not a read-only statement. It runs against \(database.dbName) on \(site.domain) and cannot be undone. Take a backup first if you are unsure.")
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $sql)
                .font(.system(size: 13, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .frame(height: 120)
                .overlay(alignment: .topLeading) {
                    if sql.isEmpty {
                        Text("SELECT * FROM users LIMIT 20")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
                .focused($editorFocused)

            ActionFeedbackView(runner: runner)

            HStack {
                if !trimmed.isEmpty {
                    Label(
                        isReadOnly ? "Read-only statement" : "Modifies data",
                        systemImage: isReadOnly ? "eye" : "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(isReadOnly ? Color.secondary : Color.orange)
                }
                Spacer()
                Button {
                    editorFocused = false
                    if isReadOnly {
                        Task { await run() }
                    } else {
                        showsWriteConfirmation = true
                    }
                } label: {
                    Label("Run", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(trimmed.isEmpty || runner.isRunning)
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private var resultArea: some View {
        if runner.isRunning {
            LoadingStateView(title: "Running…")
        } else if let result {
            if result.rows.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                        .font(.title2)
                        .foregroundStyle(.green)
                    Text(result.message ?? "Statement executed.")
                        .font(.callout)
                    if let affected = result.affectedRows {
                        Text("\(affected) row\(affected == 1 ? "" : "s") affected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                resultTable(result)
            }
        } else {
            ContentUnavailableView {
                Label("No results yet", systemImage: "tablecells")
            } description: {
                Text("Run a statement to see rows here.")
            }
        }
    }

    private func resultTable(_ result: QueryResult) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(result.rows.count) row\(result.rows.count == 1 ? "" : "s")")
                if let duration = result.durationMs {
                    Text("· \(Durations.milliseconds(duration))")
                }
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)

            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        ForEach(Array(result.columns.enumerated()), id: \.offset) { _, column in
                            Text(column)
                                .font(.caption.weight(.semibold).monospaced())
                                .frame(width: 140, alignment: .leading)
                                .padding(6)
                        }
                    }
                    .background(Color(.secondarySystemBackground))

                    ForEach(Array(result.rows.enumerated()), id: \.offset) { index, row in
                        HStack(spacing: 0) {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                Text(cell)
                                    .font(.caption.monospaced())
                                    .lineLimit(1)
                                    .frame(width: 140, alignment: .leading)
                                    .padding(6)
                            }
                        }
                        .background(index.isMultiple(of: 2) ? Color.clear : Color(.systemFill).opacity(0.35))
                    }
                }
                .textSelection(.enabled)
            }
        }
    }

    private func run() async {
        let statement = trimmed
        await runner.run("query") {
            result = try await OrchestratorAPI.shared.runQuery(
                siteID: site.id,
                databaseID: database.id,
                sql: statement
            )
        }
    }
}
