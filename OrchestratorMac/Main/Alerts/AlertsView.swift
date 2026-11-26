import OrchestratorKit
import SwiftUI

/// Every open alert across the window's width, with what it is about and since when, and
/// below it what resolved recently. "View" opens the server's or site's page.
struct AlertsView: View {
    let environment: AppEnvironment

    @State private var resolved: [FleetAlertEvent] = []
    @State private var loaded = false

    private var store: MonitorStore { environment.store }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                openSection
                resolvedSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task {
            resolved = ((try? await environment.api.fleetAlerts(active: false, limit: 50)) ?? []).filter { !$0.isActive }
            loaded = true
        }
    }

    // MARK: - Open

    private var openSection: some View {
        let items = store.overview.attention
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionHeader(title: "Open alerts", symbol: "bell.badge.fill", tint: Vivid.orange)
                Spacer()
                Text(items.isEmpty ? "None" : store.overview.alertBreakdown)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            if items.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(Color.statusSuccess)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("All systems healthy").font(.system(size: 14, weight: .semibold))
                        Text("Servers, sites and certificates have nothing open.").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(tint: .tintSuccess)
            } else {
                VStack(spacing: 0) {
                    columnsHeader(["Alert", "About", "Kind", "Since"])
                    ForEach(items) { item in
                        Divider()
                        OpenAlertRow(item: item) { environment.open($0) } renew: { siteID in
                            let executor = environment.executor
                            Task { await executor.renewCertificate(siteID: siteID) }
                        }
                    }
                }
                .card(tint: items.contains { $0.severity == .failure } ? .tintDanger : .tintWarning)
            }
        }
    }

    // MARK: - Resolved

    private var resolvedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Resolved recently", symbol: "checkmark.seal.fill", tint: Vivid.green)
            if resolved.isEmpty {
                LoadingOrEmptyRow(isLoading: !loaded, text: "Nothing resolved recently", symbol: "clock")
            } else {
                VStack(spacing: 0) {
                    columnsHeader(["Alert", "Server", "Lasted", "Resolved"])
                    ForEach(resolved.prefix(25)) { alert in
                        Divider()
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle")
                                .foregroundStyle(Color.statusSuccess)
                                .frame(width: 16)
                                .accessibilityHidden(true)
                            Text(FleetAlertKind.headline(kind: alert.kind, value: alert.value, message: alert.message))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button(alert.serverName) { environment.open(.server(serverID: alert.serverId)) }
                                .buttonStyle(.link)
                                .frame(width: 200, alignment: .leading)
                            Text(alert.resolvedAt.map { DurationText.short(Int($0.timeIntervalSince(alert.startedAt))) } ?? "—")
                                .foregroundStyle(.secondary)
                                .frame(width: 120, alignment: .leading)
                            Text(alert.resolvedAt.map { RelativeTime.ago($0) } ?? "—")
                                .foregroundStyle(.secondary)
                                .frame(width: 120, alignment: .leading)
                            Spacer().frame(width: 70)
                        }
                        .font(.system(size: 12))
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .accessibilityElement(children: .combine)
                    }
                }
                .card()
            }
        }
    }

    private func columnsHeader(_ titles: [String]) -> some View {
        HStack(spacing: 12) {
            Spacer().frame(width: 16, height: 1)
            Text(titles[0]).frame(maxWidth: .infinity, alignment: .leading)
            Text(titles[1]).frame(width: 200, alignment: .leading)
            Text(titles[2]).frame(width: 120, alignment: .leading)
            Text(titles[3]).frame(width: 120, alignment: .leading)
            Spacer().frame(width: 70, height: 1)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .accessibilityHidden(true)
    }
}

private struct OpenAlertRow: View {
    var item: AttentionItem
    var view: (DeepLink) -> Void
    var renew: (Int) -> Void

    var body: some View {
        HStack(spacing: 12) {
            StatusMarkView(mark: item.severity, size: 16)
            Text(item.title)
                .font(.system(size: 13, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(item.source)
                .frame(width: 200, alignment: .leading)
                .lineLimit(1)
            Text(item.category.capitalized)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            Text(item.since.map { "\(RelativeTime.ago($0))" } ?? "—")
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            Group {
                if case .certificate(let siteID) = item.subject {
                    Button("Renew") { renew(siteID) }
                        .help("Renew the certificate (asks for confirmation)")
                } else {
                    Button("View") { view(destination) }
                        .help("Open \(item.source)")
                }
            }
            .buttonStyle(RowButtonStyle())
            .frame(width: 70, alignment: .trailing)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 12)
        .frame(height: 40)
        .accessibilityElement(children: .combine)
    }

    private var destination: DeepLink {
        switch item.subject {
        case .server(let id, _, _): return .server(serverID: id)
        case .certificate(let id):  return .siteTab(siteID: id, tab: "ssl")
        case .siteDown(let id):     return .site(siteID: id)
        }
    }
}
