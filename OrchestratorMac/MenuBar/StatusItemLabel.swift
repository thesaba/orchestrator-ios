import OrchestratorKit
import SwiftUI

/// App glyph, status mark and alert count. No mark and no number when everything is
/// healthy; a neutral mark when the data is stale or the API cannot be reached.
struct StatusItemLabel: View {
    let environment: AppEnvironment
    var onWidthChange: (CGFloat) -> Void

    var body: some View {
        let state = StatusItemState(environment: environment)
        HStack(spacing: 4) {
            OrchestratorLogo(style: .monochrome(.primary), size: 17)
            if let mark = state.mark {
                StatusMarkView(mark: mark, size: 13)
            }
            if state.count > 0 {
                Text("\(state.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 6)
        .fixedSize()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { onWidthChange($0) }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The status item button carries the spoken label.
        .accessibilityHidden(true)
    }
}

/// What the menu bar item shows, derived from the session and the store.
@MainActor
struct StatusItemState {
    var mark: HealthMark?
    var count: Int
    var accessibilityLabel: String

    init(environment: AppEnvironment) {
        let store = environment.store
        guard environment.session.phase == .signedIn else {
            mark = nil
            count = 0
            accessibilityLabel = "Orchestrator, signed out"
            return
        }
        if store.isStale {
            mark = .unknown
            count = 0
            accessibilityLabel = store.hasLoaded ? "Orchestrator, status unknown" : "Orchestrator, loading"
            return
        }
        let overview = store.overview
        mark = overview.menuBarMark
        count = overview.alertCount
        var label = "Orchestrator, \(overview.summary)"
        if overview.isDeploying { label += ", deploy running" }
        accessibilityLabel = label
    }
}
