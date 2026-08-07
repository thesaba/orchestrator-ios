import SwiftUI

struct SitesListView: View {
    @State private var model = SitesViewModel()

    var body: some View {
        NavigationStack {
            LoadStateView(
                state: model.state,
                emptyTitle: "No sites",
                emptyMessage: "This panel has no sites yet.",
                emptyIcon: "globe",
                isEmpty: { $0.isEmpty },
                retry: { Task { await model.load() } }
            ) { _ in
                list
            }
            .navigationTitle("Sites")
            .searchable(text: $model.searchText, prompt: "Name, domain, tag")
            .refreshable { await model.load() }
            .task { if model.state.value == nil { await model.load() } }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Filter", selection: $model.filter) {
                            ForEach(SitesViewModel.Filter.allCases) { filter in
                                Text(filter.rawValue).tag(filter)
                            }
                        }
                        if !model.tags.isEmpty {
                            Divider()
                            Picker("Tag", selection: $model.selectedTag) {
                                Text("Any tag").tag(String?.none)
                                ForEach(model.tags, id: \.self) { tag in
                                    Text(tag).tag(String?.some(tag))
                                }
                            }
                        }
                    } label: {
                        Label("Filter", systemImage: model.filter == .all && model.selectedTag == nil
                              ? "line.3.horizontal.decrease.circle"
                              : "line.3.horizontal.decrease.circle.fill")
                    }
                }
            }
        }
    }

    private var list: some View {
        List {
            if model.visibleSites.isEmpty {
                ContentUnavailableView.search(text: model.searchText)
            } else {
                ForEach(model.visibleSites) { site in
                    NavigationLink {
                        SiteDetailView(siteID: site.id, initialSite: site)
                    } label: {
                        SiteRow(site: site)
                    }
                }
            }
        }
        .listStyle(.plain)
    }
}

struct SiteRow: View {
    var site: Site

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if site.pinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Text(site.name)
                    .font(.headline)
                Spacer()
                StatusBadge(status: site.statusLabel, tone: site.tone)
            }

            Text(site.domain)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                if let php = site.phpVersion {
                    Chip(text: "PHP \(php)", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                if site.sslEnabled, let days = site.sslDaysLeft {
                    Chip(text: days.daysLabel, systemImage: "lock.fill", tone: site.sslTone)
                }
                if let deployment = site.lastDeployment {
                    Chip(
                        text: deployment.createdAt.relativeShortOrDash,
                        systemImage: "arrow.up.circle",
                        tone: deployment.tone
                    )
                }
                Spacer()
            }
        }
        .padding(.vertical, 4)
    }
}

struct Chip: View {
    var text: String
    var systemImage: String?
    var tone: StatusTone = .neutral

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 9))
            }
            Text(text)
                .font(.caption2)
        }
        .foregroundStyle(tone == .neutral ? Color.secondary : tone.color)
        .lineLimit(1)
    }
}
