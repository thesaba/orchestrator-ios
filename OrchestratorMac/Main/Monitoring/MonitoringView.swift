import OrchestratorKit
import SwiftUI

/// Everything watched across the fleet: open alerts, uptime and response percentiles per
/// site, certificates, recent alert history and the alert rules. Read-only.
struct MonitoringView: View {
    let environment: AppEnvironment
    let model: MainWindowModel

    @State private var history: [FleetAlertEvent] = []
    @State private var rules: [AlertRule] = []
    @State private var loaded = false

    private var store: MonitorStore { environment.store }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Open alerts", symbol: "bell.badge.fill", tint: Vivid.orange)
                    AttentionList(environment: environment, items: store.overview.attention)
                }
                uptimeCard
                HStack(alignment: .top, spacing: 16) {
                    certificatesCard.frame(maxWidth: .infinity, alignment: .topLeading)
                    VStack(alignment: .leading, spacing: 16) {
                        historyCard
                        rulesCard
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .padding(24)
        }
        .task {
            let api = environment.api
            async let past = try? api.fleetAlerts(active: false, limit: 30)
            async let configured = try? api.alertRules()
            history = (await past ?? []).filter { !$0.isActive }
            rules = await configured ?? []
            loaded = true
        }
    }

    // MARK: - Uptime and percentiles

    private var uptimeCard: some View {
        let stats = Dictionary((model.data.apm?.sites ?? []).map { ($0.siteId, $0) }, uniquingKeysWith: { first, _ in first })
        let entries = store.uptime.filter(\.monitoring).sorted { lhs, rhs in
            if lhs.isUp != rhs.isUp { return !lhs.isUp }
            return (stats[lhs.siteId]?.p95 ?? 0) > (stats[rhs.siteId]?.p95 ?? 0)
        }
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Uptime & response · 24 h", symbol: "waveform.path.ecg", tint: Vivid.pink)
            if entries.isEmpty {
                EmptyRow(text: "No monitored sites", symbol: "waveform.path.ecg")
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Text("Site").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Now").frame(width: 70, alignment: .trailing)
                        Text("Uptime").frame(width: 64, alignment: .trailing)
                        Text("p50").frame(width: 64, alignment: .trailing)
                        Text("p95").frame(width: 64, alignment: .trailing)
                        Text("p99").frame(width: 64, alignment: .trailing)
                        Text("Checked").frame(width: 90, alignment: .trailing)
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    ForEach(entries) { entry in
                        let stat = stats[entry.siteId]
                        Divider()
                        HStack(spacing: 10) {
                            HStack(spacing: 8) {
                                StatusMarkView(mark: entry.isUp ? ((stat?.uptimePct ?? 100) < 99 ? .warning : .healthy) : .failure, size: 12)
                                Text(entry.domain).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Text(entry.isUp ? (entry.responseMs.map { "\($0) ms" } ?? "—") : (entry.statusCode.map { "HTTP \($0)" } ?? "Down"))
                                .foregroundStyle(entry.isUp ? .secondary : Color.statusDangerText)
                                .frame(width: 70, alignment: .trailing)
                            Text(stat?.uptimePct.map { "\($0)%" } ?? "—")
                                .foregroundStyle((stat?.uptimePct ?? 100) < 99 ? Color.statusWarningText : .primary)
                                .frame(width: 64, alignment: .trailing)
                            ms(stat?.p50)
                            ms(stat?.p95, warnAbove: 500)
                            ms(stat?.p99)
                            Text(entry.checkedAt.map { RelativeTime.ago($0) } ?? "—")
                                .foregroundStyle(.secondary)
                                .frame(width: 90, alignment: .trailing)
                        }
                        .font(.system(size: 12))
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .contentShape(Rectangle())
                        .onTapGesture { model.openSite(entry.siteId) }
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isButton)
                    }
                }
                .card()
            }
        }
    }

    private func ms(_ value: Int?, warnAbove: Int = .max) -> some View {
        Text(value.map { "\($0) ms" } ?? "—")
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle((value ?? 0) > warnAbove ? Color.statusWarningText : .secondary)
            .frame(width: 64, alignment: .trailing)
    }

    // MARK: - Certificates

    private var certificatesCard: some View {
        let certificates = store.certificates.sorted { ($0.daysLeft ?? .max) < ($1.daysLeft ?? .max) }
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Certificates", symbol: "lock.shield.fill", tint: Vivid.green)
            if certificates.isEmpty {
                EmptyRow(text: "No certificates", symbol: "lock")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(certificates.enumerated()), id: \.element.siteId) { index, entry in
                        if index > 0 { Divider() }
                        HStack(spacing: 10) {
                            Text(entry.domain).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                            Text(certificateText(entry))
                                .foregroundStyle(certificateColor(entry))
                        }
                        .font(.system(size: 12))
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .contentShape(Rectangle())
                        .onTapGesture { model.openSite(entry.siteId, tab: .ssl) }
                        .accessibilityElement(children: .combine)
                    }
                }
                .card()
            }
        }
    }

    private func certificateText(_ entry: SSLOverview.Entry) -> String {
        if let error = entry.error, !error.isEmpty { return "Check failed" }
        guard let days = entry.daysLeft else { return "—" }
        return days < 0 ? "Expired" : (days == 1 ? "1 day" : "\(days) days")
    }

    private func certificateColor(_ entry: SSLOverview.Entry) -> Color {
        if entry.error?.isEmpty == false { return .statusWarningText }
        guard let days = entry.daysLeft else { return .secondary }
        if days < 0 { return .statusDangerText }
        return days <= AppSettings.sslWarningDays ? .statusWarningText : .secondary
    }

    // MARK: - History and rules

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Resolved alerts", symbol: "checkmark.seal.fill", tint: Vivid.green)
            if history.isEmpty {
                LoadingOrEmptyRow(isLoading: !loaded, text: "Nothing resolved recently", symbol: "clock")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(history.prefix(10).enumerated()), id: \.element.id) { index, alert in
                        if index > 0 { Divider() }
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(FleetAlertKind.headline(kind: alert.kind, value: alert.value, message: alert.message))
                                    .font(.system(size: 12))
                                Text(alert.serverName).font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(alert.resolvedAt.map { RelativeTime.ago($0) } ?? "")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                }
                .card()
            }
        }
    }

    private var rulesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Alert rules", symbol: "slider.horizontal.3", tint: Vivid.purple, trailing: "Edit in Web Panel") { WebPanel.open(.serverAlerts) }
            if rules.isEmpty {
                LoadingOrEmptyRow(isLoading: !loaded, text: "No alert rules", symbol: "bell.slash")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rules.enumerated()), id: \.element.id) { index, rule in
                        if index > 0 { Divider() }
                        HStack(spacing: 10) {
                            Text(rule.summary).font(.system(size: 12, design: .monospaced))
                            Spacer()
                            Text(rule.enabled ? "On" : "Off")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(rule.enabled ? Color.statusSuccessText : .secondary)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .accessibilityElement(children: .combine)
                    }
                }
                .card()
            }
        }
    }
}
