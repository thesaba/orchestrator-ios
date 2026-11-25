import SwiftUI
import OrchestratorKit

/// Everything that is not a daily-driver tab.
struct MoreView: View {
    @Environment(Session.self) private var session

    var body: some View {
        NavigationStack {
            List {
                Section("Money") {
                    NavigationLink { BillingView(embedded: true) } label: {
                        Label("Billing", systemImage: "creditcard")
                    }
                }

                Section("Infrastructure") {
                    NavigationLink { ServersView() } label: {
                        Label("Servers", systemImage: "server.rack")
                    }
                    NavigationLink { DropletControlView() } label: {
                        Label("DigitalOcean", systemImage: "drop")
                    }
                    NavigationLink { SystemControlView() } label: {
                        Label("System control", systemImage: "gearshape.2")
                    }
                    NavigationLink { ServicesView() } label: {
                        Label("Services", systemImage: "square.stack.3d.up")
                    }
                }

                Section("Workspace") {
                    NavigationLink { TasksView() } label: {
                        Label("Tasks", systemImage: "checklist")
                    }
                    NavigationLink { NotesView() } label: {
                        Label("Notes", systemImage: "note.text")
                    }
                    NavigationLink { CalendarView() } label: {
                        Label("Calendar", systemImage: "calendar")
                    }
                    NavigationLink { AIAssistantView() } label: {
                        Label("AI assistant", systemImage: "sparkles")
                    }
                }

                Section("Administration") {
                    NavigationLink { AlertRulesView() } label: {
                        Label("Alert rules", systemImage: "bell.badge")
                    }
                    NavigationLink { AuditLogView() } label: {
                        Label("Audit log", systemImage: "list.bullet.rectangle")
                    }
                    if session.user?.isAdmin == true {
                        NavigationLink { UsersView() } label: {
                            Label("Users", systemImage: "person.2")
                        }
                    }
                    NavigationLink { TelegramView() } label: {
                        Label("Telegram", systemImage: "paperplane")
                    }
                    NavigationLink { DigestView() } label: {
                        Label("Weekly digest", systemImage: "envelope")
                    }
                }

                Section {
                    NavigationLink { SettingsView(embedded: true) } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .navigationTitle("More")
        }
    }
}

struct MainTabView: View {
    @State private var selection: TabIdentifier = .overview

    enum TabIdentifier: Hashable {
        case overview, sites, monitor, inbox, more
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Overview", systemImage: "square.grid.2x2", value: TabIdentifier.overview) {
                OverviewView()
            }
            Tab("Sites", systemImage: "globe", value: TabIdentifier.sites) {
                SitesListView()
            }
            Tab("Monitor", systemImage: "waveform.path.ecg", value: TabIdentifier.monitor) {
                MonitorView()
            }
            Tab("Inbox", systemImage: "bell", value: TabIdentifier.inbox) {
                InboxView()
            }
            Tab("More", systemImage: "ellipsis.circle", value: TabIdentifier.more) {
                MoreView()
            }
        }
    }
}
