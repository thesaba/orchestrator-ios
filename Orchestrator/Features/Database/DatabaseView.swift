import SwiftUI

@MainActor
@Observable
final class DatabaseViewModel {
    let site: Site

    private(set) var backups: [DatabaseBackup] = []
    private(set) var schedule: BackupSchedule?
    private(set) var s3: S3Backups?
    private(set) var databases: [SiteDatabase] = []
    private(set) var degradedSections: [String] = []

    var hasLoadedOnce = false
    let runner = ActionRunner()

    private let api: OrchestratorAPI

    init(site: Site, api: OrchestratorAPI = .shared) {
        self.site = site
        self.api = api
    }

    func load() async {
        defer { hasLoadedOnce = true }
        var degraded: [String] = []

        async let backupsTask = api.databaseBackups(siteID: site.id)
        async let scheduleTask = api.backupSchedule(siteID: site.id)
        async let s3Task = api.s3Backups(siteID: site.id)
        async let databasesTask = api.databases(siteID: site.id)

        do { backups = try await backupsTask } catch { degraded.append("Backups") }
        do { schedule = try await scheduleTask } catch { degraded.append("Schedule") }
        do { s3 = try await s3Task } catch { degraded.append("Off-site") }
        do { databases = try await databasesTask } catch { degraded.append("Databases") }

        degradedSections = degraded
    }

    func createBackup() async {
        await runner.run("backup", success: "Backup started. It appears in the list when it finishes.") { [self] in
            try await api.createDatabaseBackup(siteID: site.id)
        } onSuccess: { [self] in
            try? await Task.sleep(for: .seconds(2))
            await load()
        }
    }

    func restore(_ backup: DatabaseBackup) async {
        await runner.run("restore", success: "Restored from \(backup.name).") { [self] in
            try await api.restoreDatabaseBackup(siteID: site.id, filename: backup.name)
        }
    }

    func delete(_ backup: DatabaseBackup) async {
        await runner.run("delete-\(backup.id)", success: "Backup deleted.") { [self] in
            try await api.deleteDatabaseBackup(siteID: site.id, filename: backup.name)
        } onSuccess: { [self] in await load() }
    }

    func uploadToS3(_ backup: DatabaseBackup) async {
        await runner.run("s3-\(backup.id)", success: "Uploaded to off-site storage.") { [self] in
            try await api.uploadBackupToS3(siteID: site.id, filename: backup.name)
        } onSuccess: { [self] in await load() }
    }

    func setSchedule(active: Bool, hour: Int, minute: Int, weekdays: Set<Int>) async {
        await runner.run("schedule", success: active ? "Schedule saved." : "Schedule disabled.") { [self] in
            if active {
                try await api.enableBackupSchedule(
                    siteID: site.id, hour: hour, minute: minute,
                    days: BackupSchedule.daysString(from: weekdays)
                )
            } else {
                try await api.disableBackupSchedule(siteID: site.id)
            }
        } onSuccess: { [self] in await load() }
    }
}

struct DatabaseView: View {
    @State private var model: DatabaseViewModel
    @State private var confirmation: Confirmation?

    enum Confirmation: Identifiable {
        case restore(DatabaseBackup)
        case delete(DatabaseBackup)

        var id: String {
            switch self {
            case .restore(let backup): return "restore-\(backup.id)"
            case .delete(let backup):  return "delete-\(backup.id)"
            }
        }
    }

    init(site: Site) {
        _model = State(initialValue: DatabaseViewModel(site: site))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if !model.degradedSections.isEmpty {
                    InlineErrorBanner(message: "Could not load: \(model.degradedSections.joined(separator: ", ")).")
                }
                ActionFeedbackView(runner: model.runner)
                databasesCard
                backupsCard
                BackupScheduleCard(model: model)
                if let s3 = model.s3 { offsiteCard(s3) }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Database")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.load() }
        .task { if !model.hasLoadedOnce { await model.load() } }
        .confirmationDialog(
            confirmationTitle,
            isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }),
            titleVisibility: .visible,
            presenting: confirmation
        ) { item in
            switch item {
            case .restore(let backup):
                Button("Restore \(backup.name)", role: .destructive) {
                    Task { await model.restore(backup) }
                }
            case .delete(let backup):
                Button("Delete \(backup.name)", role: .destructive) {
                    Task { await model.delete(backup) }
                }
            }
            Button("Cancel", role: .cancel) { confirmation = nil }
        } message: { item in
            switch item {
            case .restore:
                Text("The live database is overwritten with this dump. Everything written since it was taken is lost. Take a fresh backup first.")
            case .delete:
                Text("The dump file is removed from the server permanently.")
            }
        }
    }

    private var confirmationTitle: String {
        switch confirmation {
        case .restore: return "Restore over the live database?"
        case .delete:  return "Delete this backup?"
        case nil:      return ""
        }
    }

    private var databasesCard: some View {
        SectionCard("Databases", systemImage: "cylinder") {
            if model.databases.isEmpty {
                Text("No databases registered.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(model.databases) { database in
                        NavigationLink {
                            SQLQueryView(site: model.site, database: database)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(database.dbName)
                                        .font(.callout.monospaced())
                                        .foregroundStyle(.primary)
                                    Text(database.dbUser ?? "—")
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if database.isPrimary {
                                    StatusBadge("primary", tone: .good, showsSymbol: false)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if database.id != model.databases.last?.id { Divider() }
                    }
                }
            }
        }
    }

    private var backupsCard: some View {
        SectionCard("Backups", systemImage: "externaldrive") {
            VStack(spacing: 12) {
                Button {
                    Task { await model.createBackup() }
                } label: {
                    Label("Create backup now", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.runner.isRunning)

                if model.backups.isEmpty {
                    Text("No backups yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.backups) { backup in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(backup.name)
                                .font(.caption.monospaced())
                                .lineLimit(1)
                            HStack(spacing: 12) {
                                Text(backup.sizeLabel)
                                Text(backup.createdAt.relativeShortOrDash)
                                Spacer()
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                            HStack(spacing: 14) {
                                Button("Restore") { confirmation = .restore(backup) }
                                    .foregroundStyle(.orange)
                                if model.s3?.configured == true {
                                    Button("Off-site") { Task { await model.uploadToS3(backup) } }
                                }
                                Spacer()
                                Button("Delete", role: .destructive) { confirmation = .delete(backup) }
                            }
                            .font(.caption)
                            .buttonStyle(.plain)
                            .disabled(model.runner.isRunning)
                        }
                        .padding(.vertical, 4)
                        if backup.id != model.backups.last?.id { Divider() }
                    }
                }
            }
        }
    }

    private func offsiteCard(_ s3: S3Backups) -> some View {
        SectionCard(
            "Off-site copies",
            systemImage: "cloud",
            accessory: AnyView(
                StatusBadge(s3.configured ? "configured" : "not set up",
                            tone: s3.configured ? .good : .neutral)
            )
        ) {
            if !s3.configured {
                Text("Set S3/R2 credentials in the panel's settings to enable off-site copies.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if s3.files.isEmpty {
                Text("No dumps uploaded yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(s3.files) { file in
                        HStack {
                            Image(systemName: "doc.zipper")
                                .foregroundStyle(.secondary)
                            Text(file.name)
                                .font(.caption.monospaced())
                                .lineLimit(1)
                            Spacer()
                            Text(file.sizeLabel)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

private struct BackupScheduleCard: View {
    let model: DatabaseViewModel

    @State private var hour = 3
    @State private var minute = 0
    @State private var weekdays: Set<Int> = Set(0...6)
    @State private var loaded = false

    private let weekdayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        SectionCard(
            "Automatic backups",
            systemImage: "clock.badge.checkmark",
            accessory: AnyView(
                StatusBadge(model.schedule?.active == true ? "on" : "off",
                            tone: model.schedule?.active == true ? .good : .neutral)
            )
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Picker("Hour", selection: $hour) {
                        ForEach(0..<24, id: \.self) { value in
                            Text(String(format: "%02d", value)).tag(value)
                        }
                    }
                    .pickerStyle(.menu)

                    Text(":")

                    Picker("Minute", selection: $minute) {
                        ForEach([0, 15, 30, 45], id: \.self) { value in
                            Text(String(format: "%02d", value)).tag(value)
                        }
                    }
                    .pickerStyle(.menu)

                    Spacer()
                }

                HStack(spacing: 6) {
                    ForEach(Array(weekdayNames.enumerated()), id: \.offset) { index, name in
                        Button {
                            if weekdays.contains(index) { weekdays.remove(index) } else { weekdays.insert(index) }
                        } label: {
                            Text(name.prefix(1))
                                .font(.caption.weight(.semibold))
                                .frame(width: 30, height: 30)
                                .background(
                                    weekdays.contains(index) ? Color.accentColor : Color(.tertiarySystemFill),
                                    in: Circle()
                                )
                                .foregroundStyle(weekdays.contains(index) ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        Task { await model.setSchedule(active: true, hour: hour, minute: minute, weekdays: weekdays) }
                    } label: {
                        Label(model.schedule?.active == true ? "Update" : "Enable", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    if model.schedule?.active == true {
                        Button(role: .destructive) {
                            Task { await model.setSchedule(active: false, hour: hour, minute: minute, weekdays: weekdays) }
                        } label: {
                            Label("Disable", systemImage: "xmark").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .font(.footnote)
                .disabled(model.runner.isRunning)

                if let path = model.schedule?.cronPath {
                    Text(path)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .onChange(of: model.schedule) { _, schedule in
            applyIfNeeded(schedule)
        }
        .onAppear { applyIfNeeded(model.schedule) }
    }

    private func applyIfNeeded(_ schedule: BackupSchedule?) {
        guard !loaded, let schedule else { return }
        loaded = true
        hour = schedule.hour ?? 3
        minute = schedule.minute ?? 0
        weekdays = schedule.selectedWeekdays
    }
}
