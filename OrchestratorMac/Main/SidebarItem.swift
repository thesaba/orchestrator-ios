import Foundation

/// The sidebar's groups, in order.
enum SidebarSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case infrastructure = "Infrastructure"
    case business = "Business"
    case workspace = "Workspace"
    case admin = "Admin"

    var id: String { rawValue }

    var items: [SidebarItem] { SidebarItem.allCases.filter { $0.section == self } }
}

/// One destination of the main window.
enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case dashboard, alerts
    case sites, servers, monitoring
    case billing
    case tasks, assistant
    case users, audit, automation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard:  return "Dashboard"
        case .alerts:     return "Alerts"
        case .sites:      return "Sites"
        case .servers:    return "Servers"
        case .monitoring: return "Monitoring"
        case .billing:    return "Billing"
        case .tasks:      return "Tasks & Notes"
        case .assistant:  return "AI Assistant"
        case .users:      return "Users & Access"
        case .audit:      return "Audit Log"
        case .automation: return "Automation"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard:  return "square.grid.2x2"
        case .alerts:     return "bell"
        case .sites:      return "globe"
        case .servers:    return "server.rack"
        case .monitoring: return "waveform.path.ecg"
        case .billing:    return "creditcard"
        case .tasks:      return "checklist"
        case .assistant:  return "sparkles"
        case .users:      return "person.2"
        case .audit:      return "list.bullet.rectangle"
        case .automation: return "bolt"
        }
    }

    var section: SidebarSection {
        switch self {
        case .dashboard, .alerts:              return .overview
        case .sites, .servers, .monitoring:    return .infrastructure
        case .billing:                         return .business
        case .tasks, .assistant:               return .workspace
        case .users, .audit, .automation:      return .admin
        }
    }
}
