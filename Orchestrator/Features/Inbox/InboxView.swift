import SwiftUI
import OrchestratorKit

@MainActor
@Observable
final class InboxViewModel {
    private(set) var notifications: [AppNotification] = []
    private(set) var unread: Int = 0
    private(set) var errors: [LogError] = []
    private(set) var unresolved: Int = 0

    private(set) var isLoading = false
    private(set) var loadError: APIError?

    let runner = ActionRunner()

    private let api: OrchestratorAPI

    init(api: OrchestratorAPI = .shared) {
        self.api = api
    }

    var hasLoadedOnce = false

    func load() async {
        isLoading = true
        defer { isLoading = false; hasLoadedOnce = true }

        loadError = nil
        async let notificationsTask = api.notifications()
        async let errorsTask = api.logErrors()

        do {
            let response = try await notificationsTask
            notifications = response.notifications
            unread = response.unread ?? response.notifications.filter { !$0.read }.count
        } catch {
            loadError = APIError.wrap(error)
        }
        do {
            let response = try await errorsTask
            errors = response.errors
            unresolved = response.unresolved ?? response.errors.filter { !$0.resolved && !$0.ignored }.count
        } catch {
            if loadError == nil { loadError = APIError.wrap(error) }
        }
    }

    func markRead(_ notification: AppNotification) async {
        guard !notification.read else { return }
        await runner.run("read-\(notification.id)") { [self] in
            try await api.markNotificationRead(notification.id)
        } onSuccess: { [self] in await load() }
    }

    func markAllRead() async {
        await runner.run("read-all", success: "All notifications marked read.") { [self] in
            try await api.markAllNotificationsRead()
        } onSuccess: { [self] in await load() }
    }

    func delete(_ notification: AppNotification) async {
        await runner.run("delete-\(notification.id)") { [self] in
            try await api.deleteNotification(notification.id)
        } onSuccess: { [self] in await load() }
    }
}

struct InboxView: View {
    enum Segment: String, CaseIterable, Identifiable {
        case notifications = "Notifications"
        case errors = "Errors"

        var id: String { rawValue }
    }

    @State private var model = InboxViewModel()
    @State private var segment: Segment = .notifications

    var body: some View {
        NavigationStack {
            Group {
                if let error = model.loadError, !model.hasLoadedOnce {
                    ErrorStateView(error: error) { Task { await model.load() } }
                } else if !model.hasLoadedOnce {
                    LoadingStateView()
                } else {
                    VStack(spacing: 0) {
                        if model.runner.errorMessage != nil || model.runner.successMessage != nil {
                            ActionFeedbackView(runner: model.runner)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 6)
                        }
                        list
                    }
                }
            }
            .navigationTitle("Inbox")
            .refreshable { await model.load() }
            .task { if !model.hasLoadedOnce { await model.load() } }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Section", selection: $segment) {
                        ForEach(Segment.allCases) { segment in
                            Text(segment.rawValue).tag(segment)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if segment == .notifications, model.unread > 0 {
                        Button {
                            Task { await model.markAllRead() }
                        } label: {
                            Label("Mark all read", systemImage: "checkmark.circle")
                        }
                        .disabled(model.runner.isRunning)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var list: some View {
        switch segment {
        case .notifications:
            if model.notifications.isEmpty {
                EmptyStateView(icon: "bell.slash", title: "No notifications", message: "You are all caught up.")
            } else {
                List(model.notifications) { notification in
                    NotificationRow(notification: notification)
                        .swipeActions(edge: .leading) {
                            if !notification.read {
                                Button {
                                    Task { await model.markRead(notification) }
                                } label: {
                                    Label("Read", systemImage: "checkmark")
                                }
                                .tint(.blue)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await model.delete(notification) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .onTapGesture {
                            Task { await model.markRead(notification) }
                        }
                }
                .listStyle(.plain)
            }
        case .errors:
            if model.errors.isEmpty {
                EmptyStateView(icon: "checkmark.seal", title: "No errors", message: "Nothing in the Laravel logs.")
            } else {
                List(model.errors) { error in
                    LogErrorRow(error: error)
                }
                .listStyle(.plain)
            }
        }
    }
}

struct NotificationRow: View {
    var notification: AppNotification

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: notification.symbol)
                .foregroundStyle(notification.tone.color)
                .frame(width: 22)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(notification.title)
                        .font(.callout.weight(notification.read ? .regular : .semibold))
                    Spacer()
                    Text(notification.createdAt.relativeShortOrDash)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let body = notification.body {
                    Text(body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }

            if !notification.read {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 7, height: 7)
                    .padding(.top, 6)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

struct LogErrorRow: View {
    var error: LogError

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                StatusBadge(status: error.level, tone: error.tone)
                if let domain = error.site?.domain {
                    Text(domain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let count = error.count, count > 1 {
                    Text("×\(count)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Text(error.headline)
                .font(.callout.weight(.semibold))

            if let message = error.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            HStack(spacing: 10) {
                Label(error.lastSeenAt.relativeShortOrDash, systemImage: "clock")
                if error.resolved { Label("resolved", systemImage: "checkmark") }
                if error.ignored { Label("ignored", systemImage: "bell.slash") }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
