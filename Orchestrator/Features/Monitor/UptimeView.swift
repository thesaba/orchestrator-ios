import SwiftUI
import Charts

struct UptimeView: View {
    @State private var state: LoadState<UptimeOverview> = .idle

    var body: some View {
        LoadStateView(
            state: state,
            emptyTitle: "No monitors",
            emptyMessage: "No site has uptime monitoring enabled.",
            emptyIcon: "waveform.path.ecg",
            isEmpty: { $0.sites.isEmpty },
            retry: { Task { await load() } }
        ) { overview in
            List {
                let monitored = overview.sites.filter(\.monitoring)
                let paused = overview.sites.filter { !$0.monitoring }

                if !monitored.isEmpty {
                    Section("Monitored") {
                        ForEach(monitored.sorted { !$0.isUp && $1.isUp }) { entry in
                            NavigationLink {
                                UptimeDetailView(siteID: entry.siteId, domain: entry.domain)
                            } label: {
                                row(entry)
                            }
                        }
                    }
                }
                if !paused.isEmpty {
                    Section("Not monitored") {
                        ForEach(paused) { entry in
                            Text(entry.domain)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Uptime")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { if state.value == nil { await load() } }
    }

    private func row(_ entry: UptimeOverview.Entry) -> some View {
        HStack {
            StatusDot(tone: entry.tone)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.domain)
                    .font(.callout)
                Text(entry.checkedAt.relativeShortOrDash)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Durations.milliseconds(entry.responseMs))
                    .font(.caption.monospacedDigit())
                if let code = entry.statusCode {
                    Text("HTTP \(code)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func load() async {
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await OrchestratorAPI.shared.uptime())
        } catch {
            state = .failed(APIError.wrap(error))
        }
    }
}

struct UptimeDetailView: View {
    let siteID: Int
    let domain: String

    @State private var state: LoadState<UptimeHistory> = .idle

    var body: some View {
        LoadStateView(
            state: state,
            emptyTitle: "No checks",
            emptyMessage: "No uptime checks recorded yet.",
            emptyIcon: "waveform.path.ecg",
            isEmpty: { $0.checks.isEmpty },
            retry: { Task { await load() } }
        ) { history in
            ScrollView {
                VStack(spacing: 14) {
                    SectionCard("Last 24 hours", systemImage: "chart.xyaxis.line") {
                        VStack(alignment: .leading, spacing: 10) {
                            Chart(history.checks.reversed()) { check in
                                LineMark(
                                    x: .value("Time", check.checkedAt),
                                    y: .value("ms", check.responseMs ?? 0)
                                )
                                .foregroundStyle(Color.accentColor)
                                .interpolationMethod(.monotone)

                                if !check.isUp {
                                    RuleMark(x: .value("Time", check.checkedAt))
                                        .foregroundStyle(Color.red.opacity(0.5))
                                }
                            }
                            .chartYAxisLabel("ms")
                            .frame(height: 170)

                            if let uptime = history.uptime24h {
                                Label("\(uptime)% uptime", systemImage: "checkmark.seal")
                                    .font(.caption)
                                    .foregroundStyle(uptime >= 99 ? Color.green : Color.orange)
                            }
                        }
                    }

                    SectionCard("Recent checks", systemImage: "list.bullet") {
                        VStack(spacing: 8) {
                            ForEach(history.checks.prefix(40)) { check in
                                HStack {
                                    StatusDot(tone: check.isUp ? .good : .critical)
                                    Text(check.checkedAt.shortDateTime)
                                        .font(.caption)
                                    Spacer()
                                    if let code = check.statusCode {
                                        Text("\(code)")
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(Durations.milliseconds(check.responseMs))
                                        .font(.caption.monospacedDigit())
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
        }
        .navigationTitle(domain)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { if state.value == nil { await load() } }
    }

    private func load() async {
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await OrchestratorAPI.shared.uptimeHistory(siteID: siteID))
        } catch {
            state = .failed(APIError.wrap(error))
        }
    }
}

struct CertificatesView: View {
    @State private var state: LoadState<SSLOverview> = .idle

    var body: some View {
        LoadStateView(
            state: state,
            emptyTitle: "No certificates",
            emptyMessage: "No site has SSL enabled.",
            emptyIcon: "lock.shield",
            isEmpty: { $0.sites.isEmpty },
            retry: { Task { await load() } }
        ) { overview in
            List(overview.sites.sorted { ($0.daysLeft ?? .max) < ($1.daysLeft ?? .max) }) { entry in
                HStack {
                    StatusDot(tone: entry.tone)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.domain)
                            .font(.callout)
                        Text(entry.expiresAt.shortDateTimeOrDash)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let error = entry.error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                    } else {
                        Text((entry.daysLeft ?? 0).daysLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(entry.tone.color)
                    }
                }
            }
        }
        .navigationTitle("Certificates")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { if state.value == nil { await load() } }
    }

    private func load() async {
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await OrchestratorAPI.shared.sslOverview())
        } catch {
            state = .failed(APIError.wrap(error))
        }
    }
}
