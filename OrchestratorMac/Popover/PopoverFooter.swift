import OrchestratorKit
import SwiftUI

/// "Updated 5 s ago", or the last good time and the reason when a refresh failed.
struct PopoverFooter: View {
    let store: MonitorStore
    var shortcut: KeyCombo?
    var openPalette: () -> Void = {}

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 6) {
                if let error = store.lastError {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(Color.statusWarningText)
                        .accessibilityLabel("Warning")
                    Text(lastUpdatedClock + error)
                        .lineLimit(2)
                } else if let updated = store.lastUpdated {
                    Text("Updated \(RelativeTime.ago(updated, now: context.date))")
                } else if store.isRefreshing {
                    Text("Loading…")
                }
                Spacer(minLength: 0)
                if let shortcut {
                    Button(action: openPalette) {
                        HStack(spacing: 6) {
                            KeyCap(text: shortcut.displayString)
                            Text("Command palette")
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Command palette, \(shortcut.accessibilityName)")
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var lastUpdatedClock: String {
        guard let updated = store.lastUpdated else { return "" }
        return "Last updated \(updated.formatted(date: .omitted, time: .shortened)) · "
    }
}
