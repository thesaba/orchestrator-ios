import AppKit
import OrchestratorKit
import UniformTypeIdentifiers

/// Write paths of the Files, Database and Security tabs. Each names its consequence first;
/// changes that can break the site, lose data or open access also need Touch ID.
extension CommandExecutor {
    // MARK: - Files

    func saveFile(siteID: Int, path: String, content: String) async -> Bool {
        let domain = domain(of: siteID)
        let confirmation = Confirmation(
            title: "Save \(path) on \(domain)?",
            consequence: "The file is overwritten on the server right away; there is no version history. "
                + "Code under current/ is replaced by the next deploy, so edits there are temporary. A syntax error "
                + "can take \(domain) down.",
            confirmTitle: "Save", isDestructive: true, requiresAuthentication: true)
        guard await confirm(confirmation, reason: "change \(path) on \(domain)") else { return false }
        return await perform("Could not save \(path)") { try await self.api.writeFile(siteID: siteID, path: path, content: content) }
    }

    func createItem(siteID: Int, in directory: String, folder: Bool) async -> String? {
        let domain = domain(of: siteID)
        guard let name = AlertPresenter.askText(
            title: folder ? "New Folder" : "New File",
            message: "Creates it in \(directory) on \(domain).",
            initial: folder ? "untitled folder" : "untitled.txt", confirmTitle: "Create") else { return nil }
        guard SitePath.isValidName(name) else {
            AlertPresenter.showError("That name can’t be used", "Use a name without slashes.")
            return nil
        }
        let path = SitePath.join(directory, name)
        let ok = await perform("Could not create \(name)") {
            if folder { try await self.api.makeDirectory(siteID: siteID, path: path) }
            else { try await self.api.touchFile(siteID: siteID, path: path) }
        }
        return ok ? path : nil
    }

    func renameItem(siteID: Int, path: String) async -> Bool {
        let domain = domain(of: siteID)
        let current = SitePath.components(path).last ?? path
        guard let name = AlertPresenter.askText(title: "Rename \(current)", message: "Renames it on \(domain). Code that refers to the old name stops finding it.",
                                                initial: current, confirmTitle: "Rename"), name != current else { return false }
        guard SitePath.isValidName(name) else {
            AlertPresenter.showError("That name can’t be used", "Use a name without slashes.")
            return false
        }
        let target = SitePath.join(SitePath.parent(of: path), name)
        return await perform("Could not rename \(current)") { try await self.api.renameFile(siteID: siteID, from: path, to: target) }
    }

    func deleteItems(siteID: Int, paths: [String], containsFolder: Bool) async -> Bool {
        let domain = domain(of: siteID)
        let names = paths.map { SitePath.components($0).last ?? $0 }
        let what = names.count == 1 ? names[0] : "\(names.count) items"
        let confirmation = Confirmation(
            title: "Delete \(what) from \(domain)?",
            consequence: "Deletes \(names.prefix(5).joined(separator: ", "))\(names.count > 5 ? " and more" : "") on the server"
                + (containsFolder ? ", including everything inside the folder" : "") + ". There is no trash: this cannot be undone.",
            confirmTitle: "Delete", isDestructive: true, requiresAuthentication: true)
        guard await confirm(confirmation, reason: "delete files on \(domain)") else { return false }
        return await perform("Could not delete \(what)") { try await self.api.deleteFiles(siteID: siteID, paths: paths) }
    }

    /// Picks files on this Mac and uploads them into `directory`.
    func uploadFiles(siteID: Int, to directory: String) async -> Bool {
        let domain = domain(of: siteID)
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Choose files to upload to \(directory) on \(domain)"
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return false }
        let names = panel.urls.map(\.lastPathComponent)
        let confirmation = Confirmation(
            title: "Upload \(names.count == 1 ? names[0] : "\(names.count) files") to \(directory)?",
            consequence: "Copies \(names.prefix(5).joined(separator: ", "))\(names.count > 5 ? " and more" : "") to \(domain). "
                + "A file with the same name there is replaced.",
            confirmTitle: "Upload")
        guard await confirm(confirmation, reason: "upload files to \(domain)") else { return false }
        var files: [(name: String, data: Data)] = []
        for url in panel.urls {
            guard let data = try? Data(contentsOf: url) else {
                AlertPresenter.showError("Could not read \(url.lastPathComponent)", nil)
                return false
            }
            files.append((url.lastPathComponent, data))
        }
        return await perform("Could not upload") { try await self.api.uploadFiles(siteID: siteID, destination: directory, files: files, overwrite: true) }
    }

    /// Downloads a file or a backup and saves it where the user picks. Reading only.
    func download(suggestedName: String, fetch: @escaping () async throws -> (Data, String?)) async {
        do {
            let (data, serverName) = try await fetch()
            NSApp.activate()
            let panel = NSSavePanel()
            panel.nameFieldStringValue = serverName ?? suggestedName
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try data.write(to: url)
        } catch {
            AlertPresenter.showError("Could not download \(suggestedName)", APIError.wrap(error).errorDescription)
        }
    }

    // MARK: - Database

    func createBackup(siteID: Int) async -> Bool {
        let domain = domain(of: siteID)
        let confirmation = Confirmation(
            title: "Back up the database of \(domain) now?",
            consequence: "Runs mysqldump on the server and stores a compressed copy with the other backups. "
                + "Large databases take a while and add load while it runs.",
            confirmTitle: "Back Up")
        guard await confirm(confirmation, reason: "back up \(domain)") else { return false }
        return await perform("Could not start the backup") { try await self.api.createDatabaseBackup(siteID: siteID) }
    }

    func restoreBackup(siteID: Int, backup: DatabaseBackup) async -> Bool {
        let domain = domain(of: siteID)
        let when = backup.createdAt?.formatted(date: .abbreviated, time: .shortened) ?? backup.name
        let confirmation = Confirmation(
            title: "Restore the database of \(domain) from \(when)?",
            consequence: "Every table is replaced with the copy in \(backup.name). Orders, payments, users and anything "
                + "else written since \(when) is lost. Back up now first if you might need today’s data.",
            confirmTitle: "Restore", isDestructive: true, requiresAuthentication: true)
        guard await confirm(confirmation, reason: "restore the database of \(domain)") else { return false }
        return await perform("Could not restore the backup") { try await self.api.restoreDatabaseBackup(siteID: siteID, filename: backup.name) }
    }

    func deleteBackup(siteID: Int, backup: DatabaseBackup) async -> Bool {
        let domain = domain(of: siteID)
        let confirmation = Confirmation(
            title: "Delete the backup \(backup.name)?",
            consequence: "The copy is deleted from the server of \(domain) and cannot be restored afterwards.",
            confirmTitle: "Delete", isDestructive: true, requiresAuthentication: true)
        guard await confirm(confirmation, reason: "delete a backup of \(domain)") else { return false }
        return await perform("Could not delete the backup") { try await self.api.deleteDatabaseBackup(siteID: siteID, filename: backup.name) }
    }

    func setBackupSchedule(siteID: Int, hour: Int, minute: Int, weekdays: Set<Int>) async -> Bool {
        let domain = domain(of: siteID)
        let days = BackupSchedule.daysString(from: weekdays)
        let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let dayText = days == "*" ? "every day" : weekdays.sorted().map { names[$0] }.joined(separator: ", ")
        let confirmation = Confirmation(
            title: "Back up \(domain) at \(String(format: "%02d:%02d", hour, minute)), \(dayText)?",
            consequence: "Writes a cron entry on the server that backs up the database on that schedule (server time).",
            confirmTitle: "Save Schedule")
        guard await confirm(confirmation, reason: "change the backup schedule of \(domain)") else { return false }
        return await perform("Could not save the schedule") {
            try await self.api.enableBackupSchedule(siteID: siteID, hour: hour, minute: minute, days: days)
        }
    }

    func disableBackupSchedule(siteID: Int) async -> Bool {
        let domain = domain(of: siteID)
        let confirmation = Confirmation(
            title: "Stop scheduled backups of \(domain)?",
            consequence: "The cron entry is removed. Existing backups stay; no new ones are made until you schedule them again.",
            confirmTitle: "Stop Backups", isDestructive: true)
        guard await confirm(confirmation, reason: "stop the backups of \(domain)") else { return false }
        return await perform("Could not stop the schedule") { try await self.api.disableBackupSchedule(siteID: siteID) }
    }

    /// Runs SQL. Reading statements run at once; INSERT, UPDATE and DELETE confirm with what
    /// they touch and need Touch ID. - Returns: the result, or nil when cancelled or failed.
    func runQuery(siteID: Int, database: SiteDatabase, sql: String) async -> Result<QueryResult, Error>? {
        let statement = SQLStatement(sql)
        if case .unsupported(let verb) = statement.kind {
            AlertPresenter.showError("\(verb.isEmpty ? "This statement" : verb) isn’t allowed here",
                                     "The panel runs SELECT, SHOW, DESCRIBE, EXPLAIN, INSERT, UPDATE and DELETE only.")
            return nil
        }
        if statement.isWrite {
            let domain = domain(of: siteID)
            let verb: String = { if case .write(let v) = statement.kind { return v } else { return "" } }()
            var consequence = "Runs \(verb) on \(statement.table.map { "the \($0) table" } ?? "a table") of \(database.dbName), "
                + "the production database of \(domain). There is no undo."
            if statement.affectsEveryRow {
                consequence += " There is no WHERE clause, so every row of the table changes."
            }
            if statement.isMultiple { consequence += " Only one statement is allowed at a time." }
            let confirmation = Confirmation(title: "\(verb.capitalized) data in \(database.dbName)?", consequence: consequence,
                                            confirmTitle: "Run \(verb.capitalized)", isDestructive: true, requiresAuthentication: true)
            guard await confirm(confirmation, reason: "change data in \(database.dbName)") else { return nil }
        }
        do {
            return .success(try await api.runQuery(siteID: siteID, databaseID: database.id, sql: sql))
        } catch {
            return .failure(APIError.wrap(error))
        }
    }

    // MARK: - Security

    func updateSecurity(siteID: Int, current: SiteSecurity, basicAuth: Bool, user: String, password: String,
                        ipMode: String, ipList: [String]) async -> SiteSecurity? {
        let domain = domain(of: siteID)
        var lines: [String] = []
        if basicAuth != current.basicAuth {
            lines.append(basicAuth ? "Visitors must sign in with user \(user) before they see \(domain)."
                                   : "The password prompt is removed: \(domain) is open to everyone.")
        } else if basicAuth, !password.isEmpty {
            lines.append("The password for user \(user) changes.")
        }
        let modeChanged = ipMode != (current.ipMode ?? "off") || ipList != current.ipList
        if modeChanged {
            switch ipMode {
            case "allow": lines.append("Only \(ipList.count) listed address\(ipList.count == 1 ? "" : "es") can open \(domain); everyone else gets 403. Include your own address or you lock yourself out.")
            case "deny":  lines.append("\(ipList.count) listed address\(ipList.count == 1 ? "" : "es") get 403 on \(domain).")
            default:      lines.append("Address rules are removed: anyone can reach \(domain).")
            }
        }
        if lines.isEmpty { lines.append("Nothing changes.") }
        let confirmation = Confirmation(
            title: "Change who can open \(domain)?",
            consequence: lines.joined(separator: " ") + " Nginx reloads; a config nginx rejects is not applied.",
            confirmTitle: "Apply", isDestructive: true, requiresAuthentication: true)
        guard await confirm(confirmation, reason: "change access to \(domain)") else { return nil }
        do {
            return try await api.updateSecurity(siteID: siteID, basicAuth: basicAuth, basicUser: user,
                                                basicPassword: password, ipMode: ipMode, ipList: ipList)
        } catch {
            AlertPresenter.showError("Could not change access to \(domain)", APIError.wrap(error).errorDescription)
            return nil
        }
    }

    // MARK: - Helper

    private func perform(_ failure: String, _ work: @escaping () async throws -> Void) async -> Bool {
        do {
            try await work()
            return true
        } catch {
            AlertPresenter.showError(failure, APIError.wrap(error).errorDescription)
            return false
        }
    }
}
