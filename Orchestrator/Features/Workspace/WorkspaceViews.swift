import SwiftUI
import OrchestratorKit

// MARK: - Tasks

struct TasksView: View {
    @State private var state: LoadState<[WorkTask]> = .idle
    @State private var runner = ActionRunner()
    @State private var showsComposer = false
    @State private var statusFilter: String?

    private var visible: [WorkTask] {
        let all = state.value ?? []
        guard let statusFilter else { return all }
        return all.filter { $0.status.lowercased() == statusFilter }
    }

    private var statuses: [String] {
        Array(Set((state.value ?? []).map { $0.status.lowercased() })).sorted()
    }

    var body: some View {
        LoadStateView(
            state: state,
            emptyTitle: "No tasks",
            emptyMessage: "Nothing on the list.",
            emptyIcon: "checklist",
            isEmpty: { $0.isEmpty },
            retry: { Task { await load() } }
        ) { _ in
            List {
                Section {
                    ActionFeedbackView(runner: runner)
                        .listRowBackground(Color.clear)
                }
                ForEach(visible) { task in
                    NavigationLink {
                        TaskDetailView(task: task, onChanged: { await load() })
                    } label: {
                        TaskRow(task: task)
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            Task { await toggle(task) }
                        } label: {
                            Label(task.isDone ? "Reopen" : "Done",
                                  systemImage: task.isDone ? "arrow.uturn.backward" : "checkmark")
                        }
                        .tint(task.isDone ? .orange : .green)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await delete(task) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle("Tasks")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { if state.value == nil { await load() } }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Status", selection: $statusFilter) {
                        Text("All").tag(String?.none)
                        ForEach(statuses, id: \.self) { status in
                            Text(status.capitalized).tag(String?.some(status))
                        }
                    }
                } label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showsComposer = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showsComposer) {
            TaskComposerView { draft in
                await runner.run("create", success: "Task created.") {
                    try await OrchestratorAPI.shared.createTask(draft)
                } onSuccess: { await load() }
            }
        }
    }

    private func load() async {
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await OrchestratorAPI.shared.tasks())
        } catch {
            state = .failed(APIError.wrap(error))
        }
    }

    private func toggle(_ task: WorkTask) async {
        await runner.run("toggle-\(task.id)") {
            try await OrchestratorAPI.shared.updateTask(
                id: task.id,
                TaskPatch(status: task.isDone ? "todo" : "done")
            )
        } onSuccess: { await load() }
    }

    private func delete(_ task: WorkTask) async {
        await runner.run("delete-\(task.id)", success: "Task deleted.") {
            try await OrchestratorAPI.shared.deleteTask(id: task.id)
        } onSuccess: { await load() }
    }
}

struct TaskRow: View {
    var task: WorkTask

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(task.isDone ? Color.green : Color.secondary)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.callout)
                    .strikethrough(task.isDone)
                    .foregroundStyle(task.isDone ? .secondary : .primary)

                HStack(spacing: 8) {
                    if let priority = task.priority {
                        Chip(text: priority, systemImage: "flag.fill", tone: task.priorityTone)
                    }
                    if let domain = task.site?.domain {
                        Chip(text: domain, systemImage: "globe")
                    }
                    if let progress = task.checklistProgress {
                        Chip(text: progress, systemImage: "checklist")
                    }
                    if task.commentCount > 0 {
                        Chip(text: "\(task.commentCount)", systemImage: "bubble.left")
                    }
                }

                if let due = task.dueDate {
                    Text(due.shortDate)
                        .font(.caption2)
                        .foregroundStyle(task.isOverdue ? Color.red : Color.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 3)
    }
}

struct TaskDetailView: View {
    let task: WorkTask
    var onChanged: () async -> Void

    @State private var runner = ActionRunner()
    @State private var newItem = ""
    @State private var comment = ""
    @State private var items: [WorkTask.ChecklistItem] = []

    var body: some View {
        List {
            Section {
                ActionFeedbackView(runner: runner)
                    .listRowBackground(Color.clear)
            }

            Section {
                Text(task.title)
                    .font(.headline)
                if let description = task.description, !description.isEmpty {
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    StatusBadge(status: task.status)
                    if let priority = task.priority {
                        StatusBadge(priority, tone: task.priorityTone, showsSymbol: false)
                    }
                }
            }

            Section("Details") {
                DetailRow(label: "Site", value: task.site?.domain)
                DetailRow(label: "Assignee", value: task.assignee?.email)
                DetailRow(label: "Created by", value: task.createdBy?.email)
                DetailRow(label: "Due", value: task.dueDate?.shortDate)
                DetailRow(label: "Created", value: task.createdAt.shortDateTimeOrDash)
            }

            Section("Checklist") {
                ForEach(items) { item in
                    Button {
                        Task { await toggleItem(item) }
                    } label: {
                        HStack {
                            Image(systemName: item.done ? "checkmark.square.fill" : "square")
                                .foregroundStyle(item.done ? Color.green : Color.secondary)
                            Text(item.text)
                                .strikethrough(item.done)
                                .foregroundStyle(item.done ? .secondary : .primary)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button(role: .destructive) {
                            Task { await removeItem(item) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }

                HStack {
                    TextField("Add an item", text: $newItem)
                    Button("Add") { Task { await addItem() } }
                        .disabled(newItem.trimmingCharacters(in: .whitespaces).isEmpty || runner.isRunning)
                }
            }

            Section("Comment") {
                TextField("Write a comment", text: $comment, axis: .vertical)
                    .lineLimit(2...5)
                Button("Post comment") { Task { await postComment() } }
                    .disabled(comment.trimmingCharacters(in: .whitespaces).isEmpty || runner.isRunning)
            }
        }
        .navigationTitle("Task")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { items = task.checklist ?? [] }
    }

    private func addItem() async {
        let text = newItem.trimmingCharacters(in: .whitespaces)
        await runner.run("add-item") {
            try await OrchestratorAPI.shared.addChecklistItem(taskID: task.id, text: text)
        } onSuccess: {
            newItem = ""
            await refresh()
        }
    }

    private func toggleItem(_ item: WorkTask.ChecklistItem) async {
        await runner.run("item-\(item.id)") {
            try await OrchestratorAPI.shared.setChecklistItem(taskID: task.id, itemID: item.id, done: !item.done)
        } onSuccess: { await refresh() }
    }

    private func removeItem(_ item: WorkTask.ChecklistItem) async {
        await runner.run("remove-\(item.id)") {
            try await OrchestratorAPI.shared.removeChecklistItem(taskID: task.id, itemID: item.id)
        } onSuccess: { await refresh() }
    }

    private func postComment() async {
        let body = comment.trimmingCharacters(in: .whitespaces)
        await runner.run("comment", success: "Comment posted.") {
            try await OrchestratorAPI.shared.addTaskComment(taskID: task.id, body: body)
        } onSuccess: {
            comment = ""
            await onChanged()
        }
    }

    private func refresh() async {
        if let fresh = try? await OrchestratorAPI.shared.tasks().first(where: { $0.id == task.id }) {
            items = fresh.checklist ?? []
        }
        await onChanged()
    }
}

struct TaskComposerView: View {
    var onCreate: (TaskDraft) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var description = ""
    @State private var priority = "medium"
    @State private var status = "todo"
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    @State private var sites: [Site] = []
    @State private var siteID: Int?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(2...6)
                }
                Section {
                    Picker("Priority", selection: $priority) {
                        Text("Low").tag("low")
                        Text("Medium").tag("medium")
                        Text("High").tag("high")
                        Text("Urgent").tag("urgent")
                    }
                    Picker("Status", selection: $status) {
                        Text("To do").tag("todo")
                        Text("In progress").tag("in_progress")
                        Text("Done").tag("done")
                    }
                    Picker("Site", selection: $siteID) {
                        Text("None").tag(Int?.none)
                        ForEach(sites) { site in
                            Text(site.domain).tag(Int?.some(site.id))
                        }
                    }
                }
                Section {
                    Toggle("Due date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Due", selection: $dueDate, displayedComponents: .date)
                    }
                }
            }
            .navigationTitle("New task")
            .navigationBarTitleDisplayMode(.inline)
            .task { sites = (try? await OrchestratorAPI.shared.sites()) ?? [] }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        isSaving = true
                        Task {
                            await onCreate(TaskDraft(
                                title: title.trimmingCharacters(in: .whitespaces),
                                description: description.isEmpty ? nil : description,
                                status: status,
                                priority: priority,
                                dueDate: hasDueDate ? dueDate : nil,
                                siteId: siteID,
                                assigneeId: nil
                            ))
                            dismiss()
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
    }
}

// MARK: - Notes

struct NotesView: View {
    @State private var state: LoadState<[Note]> = .idle
    @State private var runner = ActionRunner()
    @State private var search = ""
    @State private var editing: Note?
    @State private var showsComposer = false

    var body: some View {
        LoadStateView(
            state: state,
            emptyTitle: "No notes",
            emptyMessage: "Write something down.",
            emptyIcon: "note.text",
            isEmpty: { $0.isEmpty },
            retry: { Task { await load() } }
        ) { notes in
            List {
                Section {
                    ActionFeedbackView(runner: runner)
                        .listRowBackground(Color.clear)
                }
                ForEach(notes) { note in
                    Button {
                        editing = note
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                if note.pinned {
                                    Image(systemName: "pin.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                                Text(note.title)
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if note.isPublic {
                                    Image(systemName: "person.2")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if !note.preview.isEmpty {
                                Text(note.preview)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Text(note.updatedAt.relativeShortOrDash)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button(role: .destructive) {
                            Task { await delete(note) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .disabled(!note.canEdit)
                    }
                }
            }
        }
        .navigationTitle("Notes")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Search notes")
        .onSubmit(of: .search) { Task { await load() } }
        .refreshable { await load() }
        .task { if state.value == nil { await load() } }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showsComposer = true } label: { Image(systemName: "square.and.pencil") }
            }
        }
        .sheet(isPresented: $showsComposer) {
            NoteEditorView(note: nil) { draft in
                await runner.run("create", success: "Note saved.") {
                    try await OrchestratorAPI.shared.createNote(draft)
                } onSuccess: { await load() }
            }
        }
        .sheet(item: $editing) { note in
            NoteEditorView(note: note) { draft in
                await runner.run("update", success: "Note saved.") {
                    try await OrchestratorAPI.shared.updateNote(id: note.id, draft)
                } onSuccess: { await load() }
            }
        }
    }

    private func load() async {
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await OrchestratorAPI.shared.notes(search: search))
        } catch {
            state = .failed(APIError.wrap(error))
        }
    }

    private func delete(_ note: Note) async {
        await runner.run("delete-\(note.id)", success: "Note deleted.") {
            try await OrchestratorAPI.shared.deleteNote(id: note.id)
        } onSuccess: { await load() }
    }
}

struct NoteEditorView: View {
    let note: Note?
    var onSave: (NoteDraft) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var body_ = ""
    @State private var pinned = false
    @State private var isPublic = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                Section("Body") {
                    TextEditor(text: $body_)
                        .frame(minHeight: 220)
                        .font(.callout)
                }
                Section {
                    Toggle("Pinned", isOn: $pinned)
                    Toggle("Visible to the team", isOn: $isPublic)
                }
            }
            .navigationTitle(note == nil ? "New note" : "Edit note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await onSave(NoteDraft(
                                title: title.trimmingCharacters(in: .whitespaces),
                                body: body_,
                                pinned: pinned,
                                isPublic: isPublic,
                                siteId: note?.siteId
                            ))
                            dismiss()
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                title = note?.title ?? ""
                body_ = note?.body ?? ""
                pinned = note?.pinned ?? false
                isPublic = note?.isPublic ?? false
            }
        }
    }
}

// MARK: - Calendar

struct CalendarView: View {
    @State private var events: [CalendarEvent] = []
    @State private var loadError: APIError?
    @State private var runner = ActionRunner()
    @State private var month = Date()
    @State private var showsComposer = false
    @State private var hasLoaded = false

    private var range: (start: Date, end: Date) {
        let calendar = Calendar.current
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month
        let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? month
        return (start, end)
    }

    var body: some View {
        List {
            Section {
                ActionFeedbackView(runner: runner)
                    .listRowBackground(Color.clear)
            }

            Section {
                HStack {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Text(month.formatted(.dateTime.month(.wide).year()))
                        .font(.headline)
                    Spacer()
                    Button { shift(1) } label: { Image(systemName: "chevron.right") }
                }
                .buttonStyle(.plain)
            }

            if let loadError {
                Section { InlineErrorBanner(message: loadError.errorDescription ?? "Failed") }
            }

            if events.isEmpty && hasLoaded {
                Section {
                    Text("Nothing scheduled this month.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(events) { event in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        StatusDot(tone: event.tone)
                        Text(event.title)
                            .font(.callout.weight(.medium))
                        Spacer()
                        Text(event.allDay
                             ? (event.start?.shortDate ?? "—")
                             : (event.start?.shortDateTime ?? "—"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let notes = event.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(.vertical, 2)
                .swipeActions {
                    Button(role: .destructive) {
                        Task { await delete(event) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { if !hasLoaded { await load() } }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showsComposer = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showsComposer) {
            CalendarComposerView { draft in
                await runner.run("create", success: "Event created.") {
                    try await OrchestratorAPI.shared.createCalendarEvent(draft)
                } onSuccess: { await load() }
            }
        }
    }

    private func shift(_ months: Int) {
        month = Calendar.current.date(byAdding: .month, value: months, to: month) ?? month
        Task { await load() }
    }

    private func load() async {
        defer { hasLoaded = true }
        do {
            events = try await OrchestratorAPI.shared.calendarEvents(start: range.start, end: range.end)
            loadError = nil
        } catch {
            loadError = APIError.wrap(error)
        }
    }

    private func delete(_ event: CalendarEvent) async {
        await runner.run("delete-\(event.id)", success: "Event deleted.") {
            try await OrchestratorAPI.shared.deleteCalendarEvent(id: event.id)
        } onSuccess: { await load() }
    }
}

struct CalendarComposerView: View {
    var onCreate: (CalendarEventDraft) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var notes = ""
    @State private var date = Date()
    @State private var allDay = true
    @State private var type = "custom"

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(2...5)
                Toggle("All day", isOn: $allDay)
                DatePicker("Date", selection: $date,
                           displayedComponents: allDay ? .date : [.date, .hourAndMinute])
                Picker("Type", selection: $type) {
                    Text("Custom").tag("custom")
                    Text("Reminder").tag("reminder")
                    Text("Maintenance").tag("maintenance")
                }
            }
            .navigationTitle("New event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let formatter = ISO8601DateFormatter()
                        Task {
                            await onCreate(CalendarEventDraft(
                                title: title.trimmingCharacters(in: .whitespaces),
                                notes: notes.isEmpty ? nil : notes,
                                start: formatter.string(from: date),
                                end: nil,
                                allDay: allDay,
                                type: type,
                                siteId: nil
                            ))
                            dismiss()
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
