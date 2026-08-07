import SwiftUI

struct SiteLogsView: View {
    let site: Site

    @State private var state: LoadState<SiteLogsResponse> = .idle
    @State private var levelFilter: String?

    private var entries: [SiteLogsResponse.Entry] {
        let all = state.value?.entries ?? []
        guard let levelFilter else { return all }
        return all.filter { ($0.level ?? "").lowercased() == levelFilter }
    }

    private var levels: [String] {
        Array(Set((state.value?.entries ?? []).compactMap { $0.level?.lowercased() })).sorted()
    }

    var body: some View {
        LoadStateView(
            state: state,
            emptyTitle: "Log is empty",
            emptyMessage: "storage/logs/laravel.log has no entries.",
            emptyIcon: "doc.text.magnifyingglass",
            isEmpty: { $0.entries.isEmpty },
            retry: { Task { await load() } }
        ) { response in
            List {
                if let path = response.path {
                    Section {
                        Text(path)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    } footer: {
                        Text("\(response.total ?? response.entries.count) entries parsed from the tail of the file.")
                    }
                }

                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            StatusBadge(status: entry.level, tone: entry.tone)
                            if let environment = entry.environment {
                                Text(environment)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(entry.timestamp.shortDateTimeOrDash)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(entry.message)
                            .font(.caption.monospaced())
                            .lineLimit(6)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 3)
                }
            }
            .listStyle(.plain)
        }
        .navigationTitle("Laravel log")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { if state.value == nil { await load() } }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Level", selection: $levelFilter) {
                        Text("All levels").tag(String?.none)
                        ForEach(levels, id: \.self) { level in
                            Text(level.capitalized).tag(String?.some(level))
                        }
                    }
                } label: {
                    Label("Filter", systemImage: levelFilter == nil
                          ? "line.3.horizontal.decrease.circle"
                          : "line.3.horizontal.decrease.circle.fill")
                }
            }
        }
    }

    private func load() async {
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await OrchestratorAPI.shared.siteLogs(siteID: site.id))
        } catch {
            state = .failed(APIError.wrap(error))
        }
    }
}
