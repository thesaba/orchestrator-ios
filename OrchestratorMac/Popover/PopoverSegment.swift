import Observation

enum PopoverSegment: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case servers = "Servers"
    case sites = "Sites"
    case alerts = "Alerts"

    var id: String { rawValue }
}

/// UI state of the popover that outlives a single presentation.
@MainActor
@Observable
final class PopoverState {
    var segment: PopoverSegment = .overview
}
