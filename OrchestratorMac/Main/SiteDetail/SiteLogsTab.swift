import OrchestratorKit
import SwiftUI

/// The Laravel log on the left, the same errors grouped on the right.
struct SiteLogsTab: View {
    let environment: AppEnvironment
    var row: SiteTableRow

    @State private var errors: [LogError] = []
    @State private var hasLoaded = false
    @State private var showResolved = false

    var body: some View {
        HStack(spacing: 0) {
            SiteLogsView(siteID: row.id, domain: row.domain, api: environment.api)
                .frame(minWidth: 0)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Errors, grouped").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Toggle("Resolved", isOn: $showResolved).toggleStyle(.checkbox).controlSize(.small)
                }
                .padding(12)
                Divider()
                let shown = errors.filter { showResolved || !$0.resolved }
                if shown.isEmpty {
                    Text(hasLoaded ? "No errors recorded." : "Loading…")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(shown) { error in
                        LogErrorRow(error: error)
                            .listRowInsets(EdgeInsets())
                    }
                    .listStyle(.inset)
                }
            }
            .frame(width: 320)
        }
        .task(id: row.id) {
            errors = (try? await environment.api.logErrors(siteID: row.id).errors) ?? []
            hasLoaded = true
        }
    }
}
