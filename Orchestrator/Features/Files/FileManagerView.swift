import SwiftUI

@MainActor
@Observable
final class FileManagerViewModel {
    let site: Site

    private(set) var listing: FileListing?
    private(set) var state: LoadState<FileListing> = .idle

    var path: String = "/"
    var showHidden = false
    var sort: OrchestratorAPI.FileSort = .name
    var ascending = true
    var selection: Set<String> = []

    let runner = ActionRunner()

    private let api: OrchestratorAPI

    init(site: Site, api: OrchestratorAPI = .shared) {
        self.site = site
        self.api = api
    }

    var entries: [FileEntry] { listing?.entries ?? [] }
    var isSelecting: Bool { !selection.isEmpty }

    /// Path segments for the breadcrumb, each with the path to navigate to.
    var breadcrumbs: [(name: String, path: String)] {
        var result: [(String, String)] = [("root", "/")]
        var current = ""
        for part in path.split(separator: "/") {
            current += "/\(part)"
            result.append((String(part), current))
        }
        return result
    }

    func fullPath(_ entry: FileEntry) -> String {
        path.hasSuffix("/") ? path + entry.name : path + "/" + entry.name
    }

    func load() async {
        if state.value == nil { state = .loading }
        do {
            let result = try await api.files(siteID: site.id, path: path,
                                             showHidden: showHidden, sort: sort, ascending: ascending)
            listing = result
            state = .loaded(result)
        } catch {
            state = .failed(APIError.wrap(error))
        }
    }

    func open(_ entry: FileEntry) async {
        guard entry.isDirectory || entry.isSymlink else { return }
        path = fullPath(entry)
        selection.removeAll()
        state = .loading
        await load()
    }

    func navigate(to newPath: String) async {
        path = newPath
        selection.removeAll()
        state = .loading
        await load()
    }

    func goUp() async {
        guard path != "/" else { return }
        var components = path.split(separator: "/").map(String.init)
        components.removeLast()
        await navigate(to: components.isEmpty ? "/" : "/" + components.joined(separator: "/"))
    }

    // MARK: Mutations

    func createDirectory(named name: String) async {
        await runner.run("mkdir", success: "Folder created.") { [self] in
            try await api.makeDirectory(siteID: site.id, path: fullPath(name))
        } onSuccess: { [self] in await load() }
    }

    func createFile(named name: String) async {
        await runner.run("touch", success: "File created.") { [self] in
            try await api.touchFile(siteID: site.id, path: fullPath(name))
        } onSuccess: { [self] in await load() }
    }

    func delete(_ paths: [String]) async {
        await runner.run("delete", success: "Deleted \(paths.count) item\(paths.count == 1 ? "" : "s").") { [self] in
            try await api.deleteFiles(siteID: site.id, paths: paths)
        } onSuccess: { [self] in
            selection.removeAll()
            await load()
        }
    }

    func rename(_ entry: FileEntry, to newName: String) async {
        await runner.run("rename", success: "Renamed.") { [self] in
            try await api.renameFile(siteID: site.id, from: fullPath(entry), to: fullPath(newName))
        } onSuccess: { [self] in await load() }
    }

    func chmod(_ paths: [String], mode: String, recursive: Bool) async {
        await runner.run("chmod", success: "Permissions set to \(mode).") { [self] in
            try await api.chmod(siteID: site.id, paths: paths, mode: mode, recursive: recursive)
        } onSuccess: { [self] in
            selection.removeAll()
            await load()
        }
    }

    func zip(_ paths: [String], named name: String) async {
        await runner.run("zip", success: "Archive created.") { [self] in
            try await api.zipFiles(siteID: site.id, paths: paths, destination: fullPath(name))
        } onSuccess: { [self] in
            selection.removeAll()
            await load()
        }
    }

    func unzip(_ entry: FileEntry) async {
        await runner.run("unzip", success: "Extracted.") { [self] in
            try await api.unzipFile(siteID: site.id, path: fullPath(entry), destination: path)
        } onSuccess: { [self] in await load() }
    }

    private func fullPath(_ name: String) -> String {
        path.hasSuffix("/") ? path + name : path + "/" + name
    }
}

struct FileManagerView: View {
    @State private var model: FileManagerViewModel
    @State private var newItem: NewItemKind?
    @State private var newItemName = ""
    @State private var renaming: FileEntry?
    @State private var renameText = ""
    @State private var chmodTarget: [String] = []
    @State private var chmodMode = "755"
    @State private var chmodRecursive = false
    @State private var pendingDelete: [String] = []

    enum NewItemKind: String, Identifiable {
        case folder, file
        var id: String { rawValue }
    }

    init(site: Site) {
        _model = State(initialValue: FileManagerViewModel(site: site))
    }

    var body: some View {
        VStack(spacing: 0) {
            breadcrumbBar
            ActionFeedbackView(runner: model.runner)
                .padding(.horizontal, 16)

            LoadStateView(
                state: model.state,
                emptyTitle: "Empty folder",
                emptyMessage: nil,
                emptyIcon: "folder",
                isEmpty: { $0.entries.isEmpty },
                retry: { Task { await model.load() } }
            ) { _ in
                list
            }
        }
        .navigationTitle("Files")
        .navigationBarTitleDisplayMode(.inline)
        .task { if model.state.value == nil { await model.load() } }
        .refreshable { await model.load() }
        .toolbar { toolbarContent }
        .alert("New \(newItem?.rawValue ?? "item")", isPresented: Binding(
            get: { newItem != nil },
            set: { if !$0 { newItem = nil; newItemName = "" } }
        )) {
            TextField("Name", text: $newItemName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Create") {
                let name = newItemName.trimmingCharacters(in: .whitespaces)
                let kind = newItem
                newItem = nil
                newItemName = ""
                guard !name.isEmpty else { return }
                Task {
                    if kind == .folder { await model.createDirectory(named: name) }
                    else { await model.createFile(named: name) }
                }
            }
            Button("Cancel", role: .cancel) { newItem = nil; newItemName = "" }
        }
        .alert("Rename", isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )) {
            TextField("Name", text: $renameText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Rename") {
                guard let entry = renaming else { return }
                let name = renameText.trimmingCharacters(in: .whitespaces)
                renaming = nil
                guard !name.isEmpty, name != entry.name else { return }
                Task { await model.rename(entry, to: name) }
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .alert("Change permissions", isPresented: Binding(
            get: { !chmodTarget.isEmpty },
            set: { if !$0 { chmodTarget = [] } }
        )) {
            TextField("Mode (e.g. 755)", text: $chmodMode)
                .keyboardType(.numberPad)
            Button("Apply") {
                let paths = chmodTarget
                let mode = chmodMode
                let recursive = chmodRecursive
                chmodTarget = []
                Task { await model.chmod(paths, mode: mode, recursive: recursive) }
            }
            Button("Cancel", role: .cancel) { chmodTarget = [] }
        } message: {
            Text("Applied to \(chmodTarget.count) item\(chmodTarget.count == 1 ? "" : "s").")
        }
        .confirmationDialog(
            "Delete \(pendingDelete.count) item\(pendingDelete.count == 1 ? "" : "s")?",
            isPresented: Binding(get: { !pendingDelete.isEmpty }, set: { if !$0 { pendingDelete = [] } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                let paths = pendingDelete
                pendingDelete = []
                Task { await model.delete(paths) }
            }
            Button("Cancel", role: .cancel) { pendingDelete = [] }
        } message: {
            Text("Deleting is permanent — there is no trash on the server. Folders are removed with everything inside them.")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    newItem = .folder
                } label: {
                    Label("New folder", systemImage: "folder.badge.plus")
                }
                Button {
                    newItem = .file
                } label: {
                    Label("New file", systemImage: "doc.badge.plus")
                }

                Divider()

                Toggle("Show hidden", isOn: Binding(
                    get: { model.showHidden },
                    set: { model.showHidden = $0; Task { await model.load() } }
                ))

                Picker("Sort", selection: Binding(
                    get: { model.sort },
                    set: { model.sort = $0; Task { await model.load() } }
                )) {
                    ForEach(OrchestratorAPI.FileSort.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }

                if model.isSelecting {
                    Divider()
                    Button {
                        chmodTarget = Array(model.selection)
                    } label: {
                        Label("Permissions…", systemImage: "lock")
                    }
                    Button(role: .destructive) {
                        pendingDelete = Array(model.selection)
                    } label: {
                        Label("Delete selected", systemImage: "trash")
                    }
                }
            } label: {
                Label("Actions", systemImage: "ellipsis.circle")
            }
        }
    }

    private var breadcrumbBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(model.breadcrumbs.enumerated()), id: \.offset) { index, crumb in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Button(crumb.name) {
                        Task { await model.navigate(to: crumb.path) }
                    }
                    .font(.caption.weight(index == model.breadcrumbs.count - 1 ? .semibold : .regular))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    private var list: some View {
        List(selection: Binding(get: { model.selection }, set: { model.selection = $0 })) {
            ForEach(model.entries) { entry in
                row(entry)
                    .tag(model.fullPath(entry))
            }
        }
        .listStyle(.plain)
        .environment(\.editMode, .constant(model.isSelecting ? .active : .inactive))
    }

    @ViewBuilder
    private func row(_ entry: FileEntry) -> some View {
        let destinationPath = model.fullPath(entry)

        Group {
            if entry.isDirectory || entry.isSymlink {
                Button {
                    Task { await model.open(entry) }
                } label: { rowContent(entry) }
                .buttonStyle(.plain)
            } else if entry.isEditable {
                NavigationLink {
                    FileViewerView(site: model.site, path: destinationPath, name: entry.name)
                } label: { rowContent(entry) }
            } else {
                rowContent(entry)
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                pendingDelete = [destinationPath]
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button {
                renaming = entry
                renameText = entry.name
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .tint(.blue)
        }
        .contextMenu {
            Button {
                renaming = entry
                renameText = entry.name
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button {
                chmodTarget = [destinationPath]
                chmodMode = entry.permissions ?? "755"
            } label: {
                Label("Permissions…", systemImage: "lock")
            }
            if (entry.ext ?? "").lowercased() == "zip" {
                Button {
                    Task { await model.unzip(entry) }
                } label: {
                    Label("Extract here", systemImage: "doc.zipper")
                }
            }
            Button {
                model.selection.insert(destinationPath)
            } label: {
                Label("Select", systemImage: "checkmark.circle")
            }
            Divider()
            Button(role: .destructive) {
                pendingDelete = [destinationPath]
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func rowContent(_ entry: FileEntry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: entry.symbol)
                .foregroundStyle(entry.tint == .neutral ? Color.secondary : entry.tint.color)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.callout)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if !entry.isDirectory {
                        Text(Bytes.string(entry.size))
                    }
                    if let perms = entry.permsDisplay {
                        Text(perms).monospaced()
                    }
                    if let owner = entry.owner {
                        Text(owner)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Text(entry.modified.relativeShortOrDash)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

/// Read and edit one text file.
struct FileViewerView: View {
    let site: Site
    let path: String
    let name: String

    @State private var original = ""
    @State private var draft = ""
    @State private var state: LoadState<FileReadResponse> = .idle
    @State private var runner = ActionRunner()
    @State private var isEditing = false
    @State private var showsSaveConfirmation = false

    private var hasChanges: Bool { draft != original }

    var body: some View {
        Group {
            switch state {
            case .idle, .loading:
                LoadingStateView()
            case .failed(let error):
                ErrorStateView(error: error) { Task { await load() } }
            case .loaded:
                content
            }
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .task { if state.value == nil { await load() } }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isEditing {
                    Button("Save") { showsSaveConfirmation = true }
                        .disabled(!hasChanges || runner.isRunning)
                        .fontWeight(.semibold)
                } else {
                    Button("Edit") { isEditing = true }
                }
            }
        }
        .confirmationDialog(
            "Overwrite \(name)?",
            isPresented: $showsSaveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Save", role: .destructive) { Task { await save() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The file is written on the live server at \(path).")
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            ActionFeedbackView(runner: runner)
                .padding(.horizontal, 16)

            if isEditing {
                TextEditor(text: $draft)
                    .font(.system(size: 12, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(.horizontal, 8)
            } else {
                ScrollView([.horizontal, .vertical]) {
                    Text(draft)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
            }

            HStack {
                Text(path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if hasChanges {
                    Button("Revert") { draft = original }
                        .font(.caption)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    private func load() async {
        state = .loading
        do {
            let response = try await OrchestratorAPI.shared.readFile(siteID: site.id, path: path)
            original = response.content
            draft = response.content
            state = .loaded(response)
        } catch {
            state = .failed(APIError.wrap(error))
        }
    }

    private func save() async {
        await runner.run("save", success: "Saved.") {
            try await OrchestratorAPI.shared.writeFile(siteID: site.id, path: path, content: draft)
        } onSuccess: {
            original = draft
            isEditing = false
        }
    }
}
