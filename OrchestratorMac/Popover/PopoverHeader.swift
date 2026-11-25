import OrchestratorKit
import SwiftUI

/// Title, one-line summary, Refresh and Settings.
struct PopoverHeader: View {
    let environment: AppEnvironment

    private var store: MonitorStore { environment.store }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Orchestrator")
                    .font(.system(size: 15, weight: .bold))
                Text(summary.text)
                    .font(.system(size: 12))
                    .foregroundStyle(summary.color)
            }
            .accessibilityElement(children: .combine)
            Spacer()

            if environment.session.phase == .signedIn {
                Button {
                    environment.scheduler.refreshNow()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(IconButtonStyle())
                .disabled(store.isRefreshing)
                .keyboardShortcut("r", modifiers: .command)
                .help("Refresh (⌘R)")
                .accessibilityLabel("Refresh")
            }

            Button {
                environment.windows.showSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(IconButtonStyle())
            .keyboardShortcut(",", modifiers: .command)
            .help("Settings (⌘,)")
            .accessibilityLabel("Settings")
        }
    }

    private var summary: (text: String, color: Color) {
        switch environment.session.phase {
        case .launching: return ("Connecting…", .secondary)
        case .signedOut: return ("Signed out", .secondary)
        case .signedIn:  break
        }
        guard store.hasLoaded else { return ("Loading…", .secondary) }
        let overview = store.overview
        let color: Color = overview.attention.isEmpty ? .secondary : .statusWarningText
        return (overview.summary, color)
    }
}
