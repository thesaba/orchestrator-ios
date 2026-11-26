import OrchestratorKit
import SwiftUI

/// The task board (To do, In progress, Review, Done) and notes with an editor. These are the
/// team's own records, not production, so they change without a confirmation dialog.
struct TasksNotesView: View {
    let environment: AppEnvironment
    let model: MainWindowModel

    @State private var tasks: [WorkTask] = []
    @State private var notes: [Note] = []
    @State private var loaded = false
    @State private var error: String?

    @State private var openNoteID: Int?
    @State private var noteTitle = ""
    @State private var noteBody = ""
    @State private var noteDirty = false

    private var api: OrchestratorAPI { environment.api }

    var body: some View {
        HStack(spacing: 0) {
            board
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            notesPane
                .frame(width: 360)
        }
        .task { await load() }
    }

    private func load() async {
        async let taskList = try? api.tasks()
        async let noteList = try? api.notes()
        let loadedTasks = await taskList
        let loadedNotes = await noteList
        tasks = loadedTasks ?? []
        notes = loadedNotes ?? []
        error = loadedTasks == nil && loadedNotes == nil ? "Could not load tasks and notes." : nil
        loaded = true
    }

    // MARK: - Board

    private var board: some View {
        let columns = TaskColumn.board(tasks)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Tasks").font(.system(size: 13, weight: .semibold))
                Text("\(tasks.filter { !$0.isDone }.count) open").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Button("New Task…") { newTask() }.buttonStyle(.borderedProminent).controlSize(.small)
            }
            if let error { Text(error).foregroundStyle(Color.statusDangerText) }
            ScrollView {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(TaskColumn.allCases) { column in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(column.title).font(.system(size: 12, weight: .semibold))
                                Spacer()
                                Text("\(columns[column]?.count ?? 0)").font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            ForEach(columns[column] ?? []) { task in
                                TaskCard(task: task)
                                    .rightClickMenu { menu(for: task, in: column) }
                            }
                            if (columns[column] ?? []).isEmpty {
                                Text(loaded ? "Nothing here" : "Loading…").font(.system(size: 11)).foregroundStyle(.tertiary)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .card()
                    }
                }
            }
            Text("Right-click a task to move it.").font(.system(size: 11)).foregroundStyle(.tertiary)
        }
        .padding(20)
    }

    private func menu(for task: WorkTask, in column: TaskColumn) -> NSMenu {
        let menu = NSMenu(title: task.title)
        for target in TaskColumn.allCases where target != column {
            menu.addItem(ClosureMenuItem("Move to \(target.title)", symbol: "arrow.right") { move(task, to: target) })
        }
        if let siteID = task.siteId {
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem("Open Site", symbol: "globe") { model.openSite(siteID) })
        }
        return menu
    }

    private func move(_ task: WorkTask, to column: TaskColumn) {
        Task {
            do {
                try await api.updateTask(id: task.id, TaskPatch(status: column.rawValue))
                await load()
            } catch {
                AlertPresenter.showError("Could not move the task", APIError.wrap(error).errorDescription)
            }
        }
    }

    private func newTask() {
        guard let title = AlertPresenter.askText(title: "New Task", message: "It goes into To do.", confirmTitle: "Add") else { return }
        Task {
            do {
                try await api.createTask(TaskDraft(title: title, status: TaskColumn.todo.rawValue))
                await load()
            } catch {
                AlertPresenter.showError("Could not add the task", APIError.wrap(error).errorDescription)
            }
        }
    }

    // MARK: - Notes

    private var notesPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Notes").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("New Note") { newNote() }.controlSize(.small)
            }
            .padding(12)
            Divider()
            if let id = openNoteID, let note = notes.first(where: { $0.id == id }) {
                noteEditor(note)
            } else {
                List(notes) { note in
                    Button {
                        open(note)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                if note.pinned { Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(Color.accentText) }
                                Text(note.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                            }
                            Text(note.preview).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                            Text([note.updatedAt.map { "Edited \(RelativeTime.ago($0))" }, note.owner?.email].compactMap { $0 }.joined(separator: " · "))
                                .font(.system(size: 10)).foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.inset)
                .overlay { if notes.isEmpty { Text(loaded ? "No notes yet" : "Loading…").foregroundStyle(.secondary) } }
            }
        }
    }

    private func noteEditor(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button { openNoteID = nil } label: { Label("Notes", systemImage: "chevron.left") }
                    .buttonStyle(.borderless)
                Spacer()
                if note.canEdit {
                    Button("Save") { save(note) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(!noteDirty)
                        .keyboardShortcut("s", modifiers: .command)
                }
            }
            TextField("Title", text: $noteTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .semibold))
                .disabled(!note.canEdit)
                .onChange(of: noteTitle) { noteDirty = true }
            TextEditor(text: $noteBody)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .disabled(!note.canEdit)
                .onChange(of: noteBody) { noteDirty = true }
                .accessibilityLabel("Note text")
            if !note.canEdit {
                Text("Shared by \(note.owner?.email ?? "someone else"); read-only.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }

    private func open(_ note: Note) {
        openNoteID = note.id
        noteTitle = note.title
        noteBody = note.body ?? ""
        DispatchQueue.main.async { noteDirty = false }
    }

    private func save(_ note: Note) {
        let draft = NoteDraft(title: noteTitle.isEmpty ? "Untitled" : noteTitle, body: noteBody, pinned: note.pinned,
                              isPublic: note.isPublic, siteId: note.siteId)
        Task {
            do {
                try await api.updateNote(id: note.id, draft)
                noteDirty = false
                await load()
            } catch {
                AlertPresenter.showError("Could not save the note", APIError.wrap(error).errorDescription)
            }
        }
    }

    private func newNote() {
        guard let title = AlertPresenter.askText(title: "New Note", message: "Only you see it until you share it.", confirmTitle: "Create") else { return }
        Task {
            do {
                try await api.createNote(NoteDraft(title: title, body: ""))
                await load()
                if let created = notes.first(where: { $0.title == title }) { open(created) }
            } catch {
                AlertPresenter.showError("Could not create the note", APIError.wrap(error).errorDescription)
            }
        }
    }
}

private struct TaskCard: View {
    var task: WorkTask

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(task.title).font(.system(size: 12, weight: .medium)).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                if let domain = task.site?.domain { Tag(text: domain, tint: .accentText) }
                if let priority = task.priority, priority != "medium" {
                    Tag(text: priority.capitalized, tint: task.priorityTone.color)
                }
                if let progress = task.checklistProgress {
                    Text(progress).font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            if let due = task.dueDate {
                Text("Due \(due.formatted(date: .abbreviated, time: .omitted))")
                    .font(.system(size: 11))
                    .foregroundStyle(task.isOverdue ? Color.statusDangerText : .secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.quaternary))
        .accessibilityElement(children: .combine)
    }
}
