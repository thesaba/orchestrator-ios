import OrchestratorKit
import SwiftUI

/// Logo, the sections with counts, and Settings at the bottom.
struct SidebarView: View {
    let environment: AppEnvironment
    @Bindable var model: MainWindowModel

    private var store: MonitorStore { environment.store }

    var body: some View {
        List(selection: $model.selection) {
            ForEach(SidebarSection.allCases) { section in
                Section(section.rawValue) {
                    ForEach(section.items) { item in
                        Label {
                            Text(item.title)
                        } icon: {
                            Image(systemName: item.symbol)
                                .foregroundStyle(item.tint)
                                .symbolEffect(.bounce, value: item == .alerts ? store.overview.alertCount : 0)
                        }
                        .badge(badge(for: item))
                        .tag(item)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
    }

    private var header: some View {
        HStack(spacing: 10) {
            OrchestratorLogo(size: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text("Orchestrator")
                    .font(.system(size: 14, weight: .bold))
                Text(APIConfig.baseURL.host() ?? "")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                if let user = environment.session.user {
                    Text(user.initials)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.accentColor))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(user.displayName)
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(monitoringText)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 4)
                Button {
                    environment.windows.showSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("Settings")
                .accessibilityLabel("Settings")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private var monitoringText: String {
        environment.scheduler.isPaused ? "Monitoring paused" : "Monitoring every \(environment.settings.fastRefreshSeconds) s"
    }

    private func badge(for item: SidebarItem) -> Int {
        guard store.hasLoaded else { return 0 }
        switch item {
        case .alerts:  return store.overview.alertCount
        case .sites:   return store.overview.siteCounts.total
        case .servers: return store.overview.serverCounts.total
        default:       return 0
        }
    }
}
