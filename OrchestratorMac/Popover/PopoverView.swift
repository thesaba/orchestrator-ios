import OrchestratorKit
import SwiftUI

/// The menu bar popover: 400 pt wide, content height, padding 14, 12 pt between sections.
struct PopoverView: View {
    let environment: AppEnvironment
    @Bindable var state: PopoverState

    private var store: MonitorStore { environment.store }
    private var session: Session { environment.session }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PopoverHeader(environment: environment)

            switch session.phase {
            case .launching:
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 80)
            case .signedOut:
                SignedOutView { environment.windows.showSignIn() }
            case .signedIn:
                signedIn
            }
        }
        .padding(14)
        .frame(width: 400)
    }

    @ViewBuilder
    private var signedIn: some View {
        SummaryTiles(store: store) { state.segment = $0 }

        Picker("Section", selection: $state.segment) {
            ForEach(PopoverSegment.allCases) { segment in
                Text(segment.rawValue).tag(segment)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()

        if !store.hasLoaded {
            LoadingPlaceholder()
        } else {
            switch state.segment {
            case .overview:
                OverviewSection(environment: environment) { state.segment = $0 }
            case .servers:
                ScrollingList { ServerList(environment: environment, servers: store.overview.servers) }
            case .sites:
                ScrollingList { SiteList(environment: environment, sites: store.overview.sites) }
            case .alerts:
                ScrollingList { AttentionList(environment: environment, items: store.overview.attention) }
            }
        }

        PopoverFooter(store: store, shortcut: environment.settings.paletteShortcut) {
            environment.statusItem?.closePopover()
            environment.palette.show()
        }
    }
}

/// Lists in the full segments scroll once they are taller than `maxHeight`.
private struct ScrollingList<Content: View>: View {
    var maxHeight: CGFloat = 480
    @ViewBuilder var content: Content
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            content
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: min(max(contentHeight, 1), maxHeight))
    }
}
