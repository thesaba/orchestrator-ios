import Foundation
import Observation
import OrchestratorKit

/// State of the command palette: the query, the current stage (commands, branch picker,
/// Artisan picker) and the selection. Running anything goes through `CommandExecutor`.
@MainActor
@Observable
final class PaletteModel {
    enum Stage: Equatable {
        case commands
        case branches(siteID: Int, domain: String)
        case artisan(siteID: Int, domain: String)
    }

    struct Row: Identifiable, Equatable {
        enum Payload: Equatable {
            case command(PaletteCommand)
            case branch(siteID: Int, name: String)
            case artisan(siteID: Int, command: String)
        }

        var id: String
        var title: String
        var detail: String
        var symbol: String
        var needsAuthentication: Bool
        var payload: Payload
    }

    struct Section: Identifiable, Equatable {
        var title: String
        var rows: [Row]
        var id: String { title }
    }

    /// What Return does with the selected row.
    enum Activation {
        case run, runAndShowLog, chooseBranch
    }

    var stage: Stage = .commands
    var query = ""
    private(set) var selectedID: String?
    private(set) var isLoadingStage = false
    private(set) var stageError: String?
    /// Details fetched lazily for the selected row ("main · 3 commits pending").
    private(set) var detailOverrides: [String: String] = [:]

    /// Closes the panel, then runs the work (alerts need the panel out of the way).
    @ObservationIgnored var closeAndRun: ((@escaping @MainActor () async -> Void) -> Void)?

    @ObservationIgnored private let environment: AppEnvironment
    @ObservationIgnored private var branchNames: [String] = []
    @ObservationIgnored private var artisanCommands: [ArtisanCommand] = []
    @ObservationIgnored private var detailTask: Task<Void, Never>?
    @ObservationIgnored private var detailFetchedAt: [String: Date] = [:]
    /// Bumped when stage data arrives, so `sections` recomputes.
    private var stageRevision = 0

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    // MARK: - Lifecycle

    func reset() {
        stage = .commands
        query = ""
        selectedID = nil
        stageError = nil
        if environment.store.siteListings == nil {
            Task { await environment.store.refresh(includeSiteList: true) }
        }
    }

    var isLoadingSites: Bool {
        stage == .commands && environment.store.siteListings == nil
    }

    // MARK: - Rows

    var sections: [Section] {
        _ = stageRevision
        switch stage {
        case .commands:
            let store = environment.store
            let commands = CommandCatalog.commands(sites: store.siteListings ?? [], servers: store.servers)
            return CommandCatalog.rank(commands, query: query, recent: environment.settings.recentCommands).map { section in
                Section(title: section.group.title, rows: section.commands.map(row(for:)))
            }
        case .branches(let siteID, let domain):
            let matches = branchNames
                .compactMap { name in FuzzyMatcher.score(query, in: name).map { (name, $0) } }
                .sorted { query.isEmpty ? false : $0.1 > $1.1 }
            return [Section(title: "Branches of \(domain)", rows: matches.map { name, _ in
                Row(id: "branch:\(siteID):\(name)", title: name, detail: "deploy to \(domain)",
                    symbol: "arrow.triangle.branch", needsAuthentication: false,
                    payload: .branch(siteID: siteID, name: name))
            })]
        case .artisan(let siteID, let domain):
            let matches = artisanCommands
                .compactMap { command in
                    FuzzyMatcher.score(query, in: "\(command.cmd) \(command.displayName) \(command.group ?? "")").map { (command, $0) }
                }
                .sorted { query.isEmpty ? $0.0.cmd < $1.0.cmd : $0.1 > $1.1 }
            return [Section(title: "Artisan on \(domain)", rows: matches.map { command, _ in
                Row(id: "artisan:\(siteID):\(command.cmd)", title: command.cmd,
                    detail: command.description ?? command.displayName, symbol: "chevron.left.forwardslash.chevron.right",
                    needsAuthentication: ArtisanSafety.needsAuthentication(command.cmd),
                    payload: .artisan(siteID: siteID, command: command.cmd))
            })]
        }
    }

    var rows: [Row] { sections.flatMap(\.rows) }

    var effectiveSelectedID: String? {
        let all = rows
        if let selectedID, all.contains(where: { $0.id == selectedID }) { return selectedID }
        return all.first?.id
    }

    var selectedRow: Row? {
        let id = effectiveSelectedID
        return rows.first { $0.id == id }
    }

    var placeholder: String {
        switch stage {
        case .commands:                    return "Deploy, roll back, SSH…"
        case .branches(_, let domain):     return "Branch, tag or commit to deploy to \(domain)"
        case .artisan(_, let domain):      return "Artisan command for \(domain)"
        }
    }

    private func row(for command: PaletteCommand) -> Row {
        Row(id: command.id, title: command.title, detail: detailOverrides[command.id] ?? command.detail,
            symbol: command.symbol, needsAuthentication: command.requiresAuthentication, payload: .command(command))
    }

    // MARK: - Keyboard

    func moveSelection(_ delta: Int) {
        let all = rows
        guard !all.isEmpty else { return }
        let current = all.firstIndex { $0.id == effectiveSelectedID } ?? 0
        let next = min(max(current + delta, 0), all.count - 1)
        select(all[next].id)
    }

    func select(_ id: String) {
        selectedID = id
        loadDetailIfNeeded()
    }

    /// Escape: back to the command list from a picker. Returns false when already there.
    func back() -> Bool {
        guard stage != .commands else { return false }
        stage = .commands
        query = ""
        selectedID = nil
        stageError = nil
        return true
    }

    func activate(_ activation: Activation) {
        guard let row = selectedRow else {
            activateFreeText()
            return
        }
        let executor = environment.executor
        switch row.payload {
        case .command(let command):
            switch command.kind {
            case .artisan(let siteID):
                openArtisan(siteID: siteID)
            case .deploy(let siteID) where activation == .chooseBranch:
                openBranches(siteID: siteID)
            default:
                closeAndRun? { await executor.run(command, showFullLog: activation == .runAndShowLog) }
            }
        case .branch(let siteID, let name):
            environment.settings.recordRecent("deploy:\(siteID)")
            closeAndRun? { await executor.deploy(siteID: siteID, ref: name, showFullLog: activation == .runAndShowLog) }
        case .artisan(let siteID, let command):
            environment.settings.recordRecent("artisan:\(siteID)")
            closeAndRun? { await executor.runArtisan(siteID: siteID, command: command, showFullLog: activation == .runAndShowLog) }
        }
    }

    /// In the branch picker, Return with no matching branch deploys the typed ref (tag or sha).
    private func activateFreeText() {
        guard case .branches(let siteID, _) = stage else { return }
        let ref = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ref.isEmpty else { return }
        let executor = environment.executor
        closeAndRun? { await executor.deploy(siteID: siteID, ref: ref, showFullLog: false) }
    }

    // MARK: - Pickers (GET only)

    private func openBranches(siteID: Int) {
        let domain = environment.executor.domain(of: siteID)
        stage = .branches(siteID: siteID, domain: domain)
        query = ""
        selectedID = nil
        branchNames = []
        loadStage { [environment] in
            let names = try await environment.api.branches(siteID: siteID)
            let current = environment.store.siteListings?.first { $0.id == siteID }?.branch
            // The site's own branch first.
            self.branchNames = names.sorted { lhs, rhs in
                if lhs == current { return true }
                if rhs == current { return false }
                return lhs < rhs
            }
            if names.isEmpty {
                self.stageError = "No branches listed (a private repository without a token). Type a branch, tag or commit and press Return."
            }
        }
    }

    private func openArtisan(siteID: Int) {
        let domain = environment.executor.domain(of: siteID)
        stage = .artisan(siteID: siteID, domain: domain)
        query = ""
        selectedID = nil
        artisanCommands = []
        loadStage { [environment] in
            self.artisanCommands = try await environment.api.artisanCommands(siteID: siteID)
        }
    }

    private func loadStage(_ work: @escaping @MainActor () async throws -> Void) {
        isLoadingStage = true
        stageError = nil
        Task {
            do { try await work() } catch { stageError = APIError.wrap(error).errorDescription }
            isLoadingStage = false
            stageRevision += 1
        }
    }

    // MARK: - Lazy details for the selected row

    private func loadDetailIfNeeded() {
        detailTask?.cancel()
        guard case .command(let command)? = selectedRow?.payload else { return }
        if let fetched = detailFetchedAt[command.id], Date.now.timeIntervalSince(fetched) < 60 { return }
        let api = environment.api
        let branch = environment.store.siteListings?.first { $0.id == command.kind.siteID }?.branch

        detailTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            var detail: String?
            switch command.kind {
            case .deploy(let siteID):
                if let pending = try? await api.deployPending(siteID: siteID) {
                    let name = pending.branch ?? branch ?? "default branch"
                    switch (pending.upToDate, pending.commits.count) {
                    case (true, _): detail = "\(name) · up to date"
                    case (_, 0):    detail = name
                    case (_, 1):    detail = "\(name) · 1 commit pending"
                    case (_, let n): detail = "\(name) · \(n) commits pending"
                    }
                }
            case .rollback(let siteID):
                if let releases = try? await api.releases(siteID: siteID) {
                    let current = releases.current ?? releases.releases.first(where: \.isCurrent)?.name
                    let older = releases.releases.filter { release in
                        guard let current else { return true }
                        return release.name < current
                    }
                    if let target = older.max(by: { $0.name < $1.name }) {
                        detail = "to " + (target.createdAt.map { "release " + $0.formatted(.dateTime.day().month(.abbreviated).hour().minute()) }
                                          ?? ReleaseName.display(target.name))
                    } else {
                        detail = "no earlier release"
                    }
                }
            default:
                return
            }
            guard let self, !Task.isCancelled, let detail else { return }
            self.detailOverrides[command.id] = detail
            self.detailFetchedAt[command.id] = .now
        }
    }
}
