import SwiftUI
import OrchestratorKit

struct ReleasesView: View {
    let site: Site

    @State private var state: LoadState<ReleasesResponse> = .idle
    @State private var runner = ActionRunner()
    @State private var pendingRollback: ReleasesResponse.Release?

    var body: some View {
        LoadStateView(
            state: state,
            emptyTitle: "No releases",
            emptyMessage: "Nothing has been deployed to this site yet.",
            emptyIcon: "shippingbox",
            isEmpty: { $0.releases.isEmpty },
            retry: { Task { await load() } }
        ) { response in
            List {
                Section {
                    ActionFeedbackView(runner: runner)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .listRowBackground(Color.clear)
                } header: {
                    Text("Rolling back re-points the `current` symlink on the live site.")
                        .textCase(nil)
                        .font(.caption)
                }

                Section("Releases") {
                    ForEach(response.releases) { release in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(release.name)
                                    .font(.callout.monospaced())
                                Text(release.createdAt.shortDateTimeOrDash)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if release.isCurrent {
                                StatusBadge("current", tone: .good)
                            } else {
                                Button("Roll back") { pendingRollback = release }
                                    .font(.footnote)
                                    .buttonStyle(.bordered)
                                    .disabled(runner.isRunning)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle("Releases")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { if state.value == nil { await load() } }
        .confirmationDialog(
            "Roll back \(site.domain)?",
            isPresented: Binding(get: { pendingRollback != nil }, set: { if !$0 { pendingRollback = nil } }),
            titleVisibility: .visible
        ) {
            if let release = pendingRollback {
                Button("Roll back to \(release.name)", role: .destructive) {
                    Task { await rollback(to: release) }
                }
            }
            Button("Cancel", role: .cancel) { pendingRollback = nil }
        } message: {
            Text("The live site switches to this release immediately. Database migrations are not reverted.")
        }
    }

    private func load() async {
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await OrchestratorAPI.shared.releases(siteID: site.id))
        } catch {
            state = .failed(APIError.wrap(error))
        }
    }

    private func rollback(to release: ReleasesResponse.Release) async {
        pendingRollback = nil
        await runner.run("rollback", success: "Rolled back to \(release.name).") {
            try await OrchestratorAPI.shared.rollback(siteID: site.id, release: release.name)
        } onSuccess: {
            await load()
        }
    }
}
