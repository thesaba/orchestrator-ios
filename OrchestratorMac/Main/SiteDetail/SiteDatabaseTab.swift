import OrchestratorKit
import SwiftUI

/// Backups (now, scheduled, restore, download), and a SQL console. Reading statements run at
/// once; INSERT, UPDATE and DELETE confirm with what they touch and need Touch ID.
struct SiteDatabaseTab: View {
    let environment: AppEnvironment
    let siteID: Int

    @State private var backups: [DatabaseBackup] = []
    @State private var schedule: BackupSchedule?
    @State private var databases: [SiteDatabase] = []
    @State private var hasLoaded = false

    @State private var scheduleTime = Date()
    @State private var weekdays: Set<Int> = Set(0...6)

    @State private var databaseID: Int?
    @State private var sql = "SHOW TABLES;"
    @State private var result: QueryResult?
    @State private var queryError: String?
    @State private var isRunning = false

    private var executor: CommandExecutor { environment.executor }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    backupsCard.frame(maxWidth: .infinity, alignment: .topLeading)
                    scheduleCard.frame(width: 320, alignment: .topLeading)
                }
                consoleCard
            }
            .padding(24)
        }
        .task(id: siteID) { await load() }
    }

    private func load() async {
        let api = environment.api
        async let list = try? api.databaseBackups(siteID: siteID)
        async let plan = try? api.backupSchedule(siteID: siteID)
        async let dbs = try? api.databases(siteID: siteID)
        backups = await list ?? []
        schedule = await plan
        databases = await dbs ?? []
        if databaseID == nil { databaseID = (databases.first(where: \.isPrimary) ?? databases.first)?.id }
        if let schedule, schedule.active {
            scheduleTime = Calendar.current.date(bySettingHour: schedule.hour ?? 2, minute: schedule.minute ?? 0, second: 0, of: .now) ?? .now
            weekdays = schedule.selectedWeekdays
        } else {
            scheduleTime = Calendar.current.date(bySettingHour: 2, minute: 0, second: 0, of: .now) ?? .now
        }
        hasLoaded = true
    }

    private func reloadSoon(after seconds: Double = 2) {
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            await load()
        }
    }

    // MARK: - Backups

    private var backupsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionHeader(title: "Backups", symbol: "externaldrive.fill", tint: Vivid.blue)
                Spacer()
                Button("Back Up Now…") {
                    Task { if await executor.createBackup(siteID: siteID) { reloadSoon(after: 5) } }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            if backups.isEmpty {
                LoadingOrEmptyRow(isLoading: !hasLoaded, text: "No backups yet", symbol: "externaldrive")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(backups.prefix(30).enumerated()), id: \.element.id) { index, backup in
                        if index > 0 { Divider() }
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(backup.createdAt?.formatted(date: .abbreviated, time: .shortened) ?? backup.name)
                                    .font(.system(size: 12))
                                Text(backup.name).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Text(backup.sizeLabel).font(.system(size: 12)).foregroundStyle(.secondary)
                            Button("Download…") {
                                let api = environment.api, id = siteID, name = backup.name
                                Task { await executor.download(suggestedName: name) { try await api.downloadDatabaseBackup(siteID: id, filename: name) } }
                            }
                            .buttonStyle(RowButtonStyle())
                            Button("Restore…") {
                                Task { if await executor.restoreBackup(siteID: siteID, backup: backup) { reloadSoon() } }
                            }
                            .buttonStyle(RowButtonStyle())
                            .help("Asks for confirmation and Touch ID")
                            Button {
                                Task { if await executor.deleteBackup(siteID: siteID, backup: backup) { await load() } }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(RowButtonStyle())
                            .help("Delete this backup (Touch ID)")
                            .accessibilityLabel("Delete backup \(backup.name)")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                    }
                }
                .card()
            }
        }
    }

    // MARK: - Schedule

    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Schedule", symbol: "calendar.badge.clock", tint: Vivid.purple)
            VStack(alignment: .leading, spacing: 10) {
                Text(scheduleSummary).font(.system(size: 12)).foregroundStyle(.secondary)
                DatePicker("Time", selection: $scheduleTime, displayedComponents: .hourAndMinute)
                    .font(.system(size: 12))
                HStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { day in
                        let names = ["S", "M", "T", "W", "T", "F", "S"]
                        let full = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
                        Toggle(names[day], isOn: Binding(
                            get: { weekdays.contains(day) },
                            set: { on in if on { weekdays.insert(day) } else { weekdays.remove(day) } }))
                            .toggleStyle(.button)
                            .controlSize(.small)
                            .accessibilityLabel(full[day])
                    }
                }
                HStack {
                    if schedule?.active == true {
                        Button("Stop…") {
                            Task { if await executor.disableBackupSchedule(siteID: siteID) { await load() } }
                        }
                    }
                    Spacer()
                    Button(schedule?.active == true ? "Save…" : "Schedule…") {
                        let parts = Calendar.current.dateComponents([.hour, .minute], from: scheduleTime)
                        let days = weekdays
                        Task {
                            if await executor.setBackupSchedule(siteID: siteID, hour: parts.hour ?? 2, minute: parts.minute ?? 0, weekdays: days) {
                                await load()
                            }
                        }
                    }
                    .disabled(weekdays.isEmpty)
                }
                .controlSize(.small)
            }
            .padding(12)
            .card()
        }
    }

    private var scheduleSummary: String {
        guard let schedule else { return hasLoaded ? "Could not read the schedule." : "Loading…" }
        guard schedule.active else { return "No scheduled backups." }
        return "Every \(schedule.daysLabel == "Every day" ? "day" : schedule.daysLabel) at \(schedule.timeLabel) (server time)."
    }

    // MARK: - Console

    private var consoleCard: some View {
        let statement = SQLStatement(sql)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionHeader(title: "SQL console", symbol: "terminal.fill", tint: Vivid.indigo)
                Spacer()
                if databases.count > 1 {
                    Picker("Database", selection: $databaseID) {
                        ForEach(databases) { Text($0.dbName).tag(Optional($0.id)) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .controlSize(.small)
                } else if let db = databases.first {
                    Text(db.dbName).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: $sql)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .background(Color.logGround)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .frame(height: 96)
                    .autocorrectionDisabled()
                    .accessibilityLabel("SQL statement")
                HStack(spacing: 10) {
                    Text(statementNote(statement))
                        .font(.system(size: 11))
                        .foregroundStyle(statement.isWrite ? Color.statusWarningText : .secondary)
                    Spacer()
                    if let result {
                        Text(resultSummary(result)).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Button(statement.isWrite ? "Run…" : "Run") { run() }
                        .buttonStyle(.borderedProminent)
                        .disabled(isRunning || databaseID == nil || sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .keyboardShortcut(.return, modifiers: .command)
                }
                .controlSize(.small)
                if let queryError {
                    Text(queryError)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.statusDangerText)
                        .textSelection(.enabled)
                } else if let result, !result.columns.isEmpty {
                    ResultGrid(result: result)
                }
            }
            .padding(12)
            .card()
        }
    }

    private func statementNote(_ statement: SQLStatement) -> String {
        switch statement.kind {
        case .read: return "Reads only · runs without asking"
        case .write(let verb):
            return "\(verb) changes production data · asks for confirmation and Touch ID"
                + (statement.affectsEveryRow ? " · no WHERE: every row" : "")
        case .unsupported(let verb): return verb.isEmpty ? " " : "\(verb) is not allowed by the panel"
        }
    }

    private func resultSummary(_ result: QueryResult) -> String {
        var parts = ["\(result.rows.count) row\(result.rows.count == 1 ? "" : "s")"]
        if result.truncated { parts.append("first 1000 shown") }
        if let ms = result.durationMs { parts.append("\(ms) ms") }
        return parts.joined(separator: " · ")
    }

    private func run() {
        guard let database = databases.first(where: { $0.id == databaseID }) else { return }
        let text = sql
        isRunning = true
        Task {
            defer { isRunning = false }
            guard let outcome = await executor.runQuery(siteID: siteID, database: database, sql: text) else { return }
            switch outcome {
            case .success(let value):
                result = value
                queryError = nil
            case .failure(let error):
                result = nil
                queryError = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}

/// Query rows in fixed-width columns that scroll sideways and down.
private struct ResultGrid: View {
    var result: QueryResult
    private let width: CGFloat = 170

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(Array(result.rows.prefix(1000).enumerated()), id: \.offset) { index, row in
                        HStack(spacing: 0) {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                Text(cell)
                                    .foregroundStyle(cell == "NULL" ? .tertiary : .primary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .frame(width: width, alignment: .leading)
                                    .padding(.horizontal, 6)
                                    .help(cell)
                            }
                        }
                        .frame(height: 24)
                        .background(index.isMultiple(of: 2) ? Color.clear : Color.secondary.opacity(0.06))
                    }
                } header: {
                    HStack(spacing: 0) {
                        ForEach(result.columns, id: \.self) { column in
                            Text(column)
                                .fontWeight(.semibold)
                                .lineLimit(1)
                                .frame(width: width, alignment: .leading)
                                .padding(.horizontal, 6)
                        }
                    }
                    .frame(height: 26)
                    .background(.bar)
                }
            }
            .font(.system(size: 12, design: .monospaced))
            .textSelection(.enabled)
        }
        .frame(minHeight: 120, maxHeight: 360)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
