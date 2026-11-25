import Foundation
import OrchestratorKit

@MainActor
@Observable
final class SitesViewModel {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case attention = "Attention"
        case suspended = "Suspended"
        case maintenance = "Maintenance"

        var id: String { rawValue }
    }

    private(set) var state: LoadState<[Site]> = .idle
    private(set) var tags: [String] = []

    var searchText = ""
    var filter: Filter = .all
    var selectedTag: String?

    private let api: OrchestratorAPI

    init(api: OrchestratorAPI = .shared) {
        self.api = api
    }

    var allSites: [Site] { state.value ?? [] }

    var visibleSites: [Site] {
        var result = allSites

        switch filter {
        case .all:         break
        case .attention:   result = result.filter { $0.tone == .critical || $0.tone == .warning }
        case .suspended:   result = result.filter(\.billingSuspended)
        case .maintenance: result = result.filter(\.maintenanceMode)
        }

        if let selectedTag {
            result = result.filter { $0.tagList.contains(selectedTag) }
        }

        let needle = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !needle.isEmpty {
            result = result.filter { $0.searchHaystack.contains(needle) }
        }

        // Pinned first, then anything unhealthy, then alphabetical.
        return result.sorted { lhs, rhs in
            if lhs.pinned != rhs.pinned { return lhs.pinned }
            let lhsBad = lhs.tone == .critical
            let rhsBad = rhs.tone == .critical
            if lhsBad != rhsBad { return lhsBad }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    func load() async {
        if state.value == nil { state = .loading }
        do {
            let sites = try await api.sites()
            state = .loaded(sites)
        } catch {
            state = .failed(APIError.wrap(error))
        }
        // Tag list is cosmetic — never let it break the screen.
        tags = (try? await api.siteTags()) ?? []
    }
}
