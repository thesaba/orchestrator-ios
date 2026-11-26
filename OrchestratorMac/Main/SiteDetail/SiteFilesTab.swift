import OrchestratorKit
import SwiftUI

/// A Finder-style list of the site's files with a breadcrumb, and the selected file in a
/// preview or editor beside it. Everything is relative to the site's root folder.
struct SiteFilesTab: View {
    let environment: AppEnvironment
    let siteID: Int

    @State private var directory = "/"
    @State private var listing: FileListing?
    @State private var selection: String?
    @State private var showHidden = false
    @State private var error: String?
    @State private var isLoading = false

    @State private var openFile: String?
    @State private var file: FileReadResponse?
    @State private var original = ""
    @State private var draft = ""
    @State private var fileError: String?
    @State private var isSaving = false

    private var executor: CommandExecutor { environment.executor }

    var body: some View {
        HStack(spacing: 0) {
            browser
                .frame(minWidth: 320, idealWidth: 420, maxWidth: 520)
            Divider()
            preview
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: "\(siteID)\(directory)\(showHidden)") { await load() }
    }

    // MARK: - Browser

    private var browser: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Button { navigate("/") } label: { Image(systemName: "house") }
                    .buttonStyle(.borderless)
                    .help("Site root")
                    .accessibilityLabel("Site root")
                ForEach(SitePath.breadcrumbs(directory), id: \.path) { crumb in
                    Text("›").foregroundStyle(.tertiary)
                    Button(crumb.name) { navigate(crumb.path) }
                        .buttonStyle(.link)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 12)
            .frame(height: 32)

            HStack(spacing: 6) {
                Button { create(folder: true) } label: { Image(systemName: "folder.badge.plus") }
                    .help("New folder")
                    .accessibilityLabel("New folder")
                Button { create(folder: false) } label: { Image(systemName: "doc.badge.plus") }
                    .help("New file")
                    .accessibilityLabel("New file")
                Button { upload() } label: { Image(systemName: "square.and.arrow.up") }
                    .help("Upload files from this Mac")
                    .accessibilityLabel("Upload files")
                Spacer()
                Toggle("Hidden", isOn: $showHidden).toggleStyle(.checkbox)
                Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
                    .help("Reload")
                    .accessibilityLabel("Reload")
            }
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
            Divider()

            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Color.statusDangerText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let listing {
                List(selection: $selection) {
                    if directory != "/" {
                        row(name: "..", symbol: "arrowshape.turn.up.left", size: "", modified: "")
                            .tag("..")
                    }
                    ForEach(listing.entries) { entry in
                        row(name: entry.name, symbol: entry.symbol,
                            size: entry.isDirectory || entry.isSymlink ? "" : Bytes.string(entry.size),
                            modified: entry.modified.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "",
                            isFolder: entry.isDirectory || entry.isSymlink)
                            .tag(entry.name)
                            .rightClickMenu { menu(for: entry) }
                    }
                }
                .listStyle(.inset)
                .contextMenu(forSelectionType: String.self) { _ in } primaryAction: { names in
                    if let name = names.first { activate(name) }
                }
                .onChange(of: selection) { _, name in
                    guard let name, name != "..", let entry = listing.entries.first(where: { $0.name == name }),
                          !entry.isDirectory, !entry.isSymlink else { return }
                    openPreview(SitePath.join(directory, name))
                }
                .overlay {
                    if listing.entries.isEmpty {
                        Text("Empty folder").foregroundStyle(.secondary)
                    }
                }
            } else {
                SkeletonRows(count: 8, rowHeight: 28).padding(12).frame(maxHeight: .infinity, alignment: .top)
            }
            if let root = listing?.rootPath {
                Text(root + (directory == "/" ? "" : directory))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
        }
    }

    private func row(name: String, symbol: String, size: String, modified: String, isFolder: Bool = false) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(isFolder ? Color.accentText : .secondary)
                .frame(width: 16)
            Text(name).lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(size).foregroundStyle(.secondary).frame(width: 64, alignment: .trailing)
            Text(modified).foregroundStyle(.secondary).frame(width: 84, alignment: .trailing)
        }
        .font(.system(size: 12))
        .accessibilityElement(children: .combine)
        .help(isFolder ? "Double-click to open" : name)
    }

    private func menu(for entry: FileEntry) -> NSMenu {
        let path = SitePath.join(directory, entry.name)
        let menu = NSMenu(title: entry.name)
        if entry.isDirectory || entry.isSymlink {
            menu.addItem(ClosureMenuItem("Open", symbol: "folder") { navigate(path) })
        } else {
            menu.addItem(ClosureMenuItem("Open", symbol: "doc.text") { openPreview(path) })
            menu.addItem(ClosureMenuItem("Download…", symbol: "arrow.down.circle") {
                let api = environment.api, id = siteID
                Task { await executor.download(suggestedName: entry.name) { try await api.downloadFile(siteID: id, path: path) } }
            })
        }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Rename…", symbol: "pencil") {
            Task { if await executor.renameItem(siteID: siteID, path: path) { await load() } }
        })
        menu.addItem(ClosureMenuItem("Delete…  (Touch ID)", symbol: "trash") {
            Task {
                if await executor.deleteItems(siteID: siteID, paths: [path], containsFolder: entry.isDirectory) {
                    if openFile == path { closePreview() }
                    await load()
                }
            }
        })
        return menu
    }

    private func activate(_ name: String) {
        if name == ".." { navigate(SitePath.parent(of: directory)); return }
        guard let entry = listing?.entries.first(where: { $0.name == name }) else { return }
        let path = SitePath.join(directory, name)
        // A symlink here is almost always a folder (`current` → the live release).
        entry.isDirectory || entry.isSymlink ? navigate(path) : openPreview(path)
    }

    private func navigate(_ path: String) {
        selection = nil
        directory = path
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            listing = try await environment.api.files(siteID: siteID, path: directory, showHidden: showHidden)
            error = nil
        } catch {
            self.error = APIError.wrap(error).errorDescription
        }
    }

    private func create(folder: Bool) {
        let dir = directory
        Task {
            if let path = await executor.createItem(siteID: siteID, in: dir, folder: folder) {
                await load()
                if !folder { openPreview(path) }
            }
        }
    }

    private func upload() {
        let dir = directory
        Task { if await executor.uploadFiles(siteID: siteID, to: dir) { await load() } }
    }

    // MARK: - Preview and editor

    @ViewBuilder
    private var preview: some View {
        if let openFile {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Text(openFile)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.head)
                    if draft != original {
                        Text("Edited · not saved").font(.system(size: 11)).foregroundStyle(Color.statusWarningText)
                    }
                    Spacer()
                    if let file {
                        Text([file.mime, file.size.map { Bytes.string($0) }].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Button("Download…") {
                        let api = environment.api, id = siteID, path = openFile
                        let name = SitePath.components(path).last ?? "file"
                        Task { await executor.download(suggestedName: name) { try await api.downloadFile(siteID: id, path: path) } }
                    }
                    if file?.binary == false {
                        Button("Revert") { draft = original }
                            .disabled(draft == original || isSaving)
                        Button("Save…") { save(openFile) }
                            .buttonStyle(.borderedProminent)
                            .disabled(draft == original || isSaving)
                            .keyboardShortcut("s", modifiers: .command)
                    }
                }
                .controlSize(.small)
                .padding(.horizontal, 16)
                .frame(height: 44)
                Divider()
                fileBody
            }
        } else {
            ContentUnavailableView("No file open", systemImage: "doc.text",
                                   description: Text("Select a file to see it here. Text files can be edited."))
        }
    }

    @ViewBuilder
    private var fileBody: some View {
        if let fileError {
            Label(fileError, systemImage: "exclamationmark.triangle")
                .foregroundStyle(Color.statusDangerText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let file {
            if file.binary {
                if (file.mime ?? "").hasPrefix("image/"), let data = Data(base64Encoded: file.content),
                   let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView("Binary file", systemImage: "doc",
                                           description: Text("It can’t be shown here. Download it to open it on this Mac."))
                }
            } else {
                TextEditor(text: $draft)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .background(Color.logGround)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Contents of \(openFile ?? "file")")
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(0..<14, id: \.self) { line in SkeletonBar(width: CGFloat([340, 220, 410, 180, 300, 260][line % 6]), height: 9) }
            }
            .padding(20)
            .shimmering()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func openPreview(_ path: String) {
        guard path != openFile else { return }
        if draft != original, openFile != nil {
            let keep = AlertPresenter.confirm(Confirmation(
                title: "Discard your changes to \(openFile ?? "")?",
                consequence: "They were not saved to the server.", confirmTitle: "Discard"))
            guard keep else { return }
        }
        openFile = path
        file = nil
        fileError = nil
        Task {
            do {
                let response = try await environment.api.readFile(siteID: siteID, path: path)
                guard openFile == path else { return }
                file = response
                original = response.binary ? "" : response.content
                draft = original
            } catch {
                guard openFile == path else { return }
                fileError = APIError.wrap(error).errorDescription
            }
        }
    }

    private func closePreview() {
        openFile = nil
        file = nil
        original = ""
        draft = ""
    }

    private func save(_ path: String) {
        let content = draft
        isSaving = true
        Task {
            defer { isSaving = false }
            if await executor.saveFile(siteID: siteID, path: path, content: content) {
                original = content
                await load()
            }
        }
    }
}
