import Charts
import OrchestratorKit
import SwiftUI

/// One server: header with SSH and Reboot, metric charts over a range, processes, services,
/// containers, updates, the disk forecast and its open alerts.
struct ServerDetailView: View {
    let environment: AppEnvironment
    @Bindable var model: MainWindowModel
    let serverID: Int

    @State private var range: MetricsRange = .day
    @State private var points: [FleetMetricsHistory.Point] = []
    @State private var metricsLoaded = false
    @State private var metricsExpanded = false
    @State private var processes: [FleetProcesses.Process] = []
    @State private var byMemory = false
    @State private var inventory: FleetInventory?
    @State private var inventoryAt: Date?
    @State private var forecast: [FleetForecast.Mount] = []
    @State private var loaded = false
    @State private var section: ServerSection = .overview

    enum ServerSection: Hashable { case overview, logs, terminal }

    private var store: MonitorStore { environment.store }
    private var status: ServerStatus? { store.server(id: serverID) }
    private var executor: CommandExecutor { environment.executor }

    var body: some View {
        Group {
            if let status {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 12) {
                        header(status)
                        Picker("Section", selection: $section) {
                            Label("Overview", systemImage: "square.grid.2x2").tag(ServerSection.overview)
                            Label("Logs", systemImage: "text.alignleft").tag(ServerSection.logs)
                            Label("Terminal", systemImage: "apple.terminal").tag(ServerSection.terminal)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 12)
                    Divider()
                    if section == .terminal {
                        ServerTerminalSection(environment: environment, server: status.server)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if section == .logs {
                        ServerLogsView(api: environment.api, serverID: status.server.id,
                                       services: (inventory?.services ?? []).map(\.name))
                    } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        charts
                        HStack(alignment: .top, spacing: 16) {
                            VStack(alignment: .leading, spacing: 16) {
                                processesCard
                                servicesCard(status)
                            }
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            VStack(alignment: .leading, spacing: 16) {
                                alertsCard(status)
                                forecastCard
                                updatesCard(status)
                                containersCard(status)
                            }
                            .frame(width: 340, alignment: .topLeading)
                        }
                    }
                    .padding(24)
                }
                    }
                }
            } else {
                ContentUnavailableView {
                    Label("Server not found", systemImage: "server.rack")
                } actions: {
                    Button("Back to Servers") { model.openServerID = nil }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { model.openServerID = nil } label: { Label("Servers", systemImage: "chevron.left") }
                    .help("Back to all servers")
                    .keyboardShortcut("[", modifiers: .command)
            }
        }
        .sheet(isPresented: $metricsExpanded) {
            ServerMetricsSheet(api: environment.api, serverID: serverID, serverName: status?.server.name ?? "Server", range: range)
        }
        .task(id: serverID) { await loadDetails() }
        .task(id: "\(serverID)-\(range.rawValue)") { await loadMetrics() }
        .task(id: "\(serverID)-\(byMemory)") { await loadProcesses() }
    }

    // MARK: - Loading (all GET)

    private func loadDetails() async {
        let api = environment.api
        async let inv = try? api.fleetInventory(serverID: serverID)
        async let disks = try? api.fleetForecast(serverID: serverID)
        let response = await inv
        inventory = response?.inventory
        inventoryAt = response?.at
        forecast = await disks?.mounts ?? []
        loaded = true
    }

    private func loadMetrics() async {
        points = (try? await environment.api.fleetMetrics(serverID: serverID, range: range).points) ?? []
        metricsLoaded = true
    }

    private func loadProcesses() async {
        processes = (try? await environment.api.fleetProcesses(serverID: serverID, sortByMemory: byMemory, limit: 15).processes) ?? []
    }

    private func reloadSoon() {
        Task {
            try? await Task.sleep(for: .seconds(4))
            await loadDetails()
        }
    }

    // MARK: - Header

    private func header(_ status: ServerStatus) -> some View {
        let server = status.server
        return HStack(spacing: 12) {
            Image(systemName: "server.rack")
                .font(.system(size: 16))
                .foregroundStyle(status.mark == .healthy ? Color.accentText : status.mark.textTint)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(status.mark == .healthy ? Color.tintInfo : Color.tintWarning))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(server.name).font(.system(size: 18, weight: .semibold)).textSelection(.enabled)
                Text(headerDetail(server)).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            }
            Text(status.label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(status.mark == .healthy ? Color.statusSuccessText : status.mark.textTint)
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(Capsule().fill(status.mark == .healthy ? Color.tintSuccess : (status.mark == .failure ? Color.tintDanger : Color.tintWarning)))
            Spacer(minLength: 12)
            if server.isLocal || server.hasSsh || server.host != nil {
                Button("Open in Terminal") {
                    let id = server.id
                    Task { await executor.openSSH(serverID: id) }
                }
            }
            Button("Web Panel") { WebPanel.open(.server(id: server.id)) }
            Button("Reboot…") {
                let id = server.id, name = server.name
                Task { if await executor.runFleetAction(serverID: id, serverName: name, .reboot(delayMinutes: 0)) { reloadSoon() } }
            }
            .help("Asks for confirmation and Touch ID")
            .disabled(server.channel == "none")
        }
    }

    private func headerDetail(_ server: FleetServer) -> String {
        var parts: [String] = []
        if let os = inventory?.os, !os.isEmpty { parts.append(os) }
        if let cores = server.latest?.m.cpu.cores { parts.append("\(cores) cores") }
        if let location = server.location { parts.append(location) }
        parts.append(server.isLocal ? "panel host" : "via \(server.channel)")
        if server.agentStatus == "online", let version = server.agentVersion { parts.append("agent \(version)") }
        if let uptime = server.latest?.m.uptime { parts.append("up \(Int(uptime / 86_400)) days") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Charts

    private var charts: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionHeader(title: "Metrics", symbol: "chart.xyaxis.line", tint: Vivid.indigo)
                Picker("Range", selection: $range) {
                    ForEach(MetricsRange.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .controlSize(.small)
                ExpandChartButton { metricsExpanded = true }
            }
            HStack(spacing: 10) {
                if !metricsLoaded {
                    SkeletonChart(height: 160); SkeletonChart(height: 160); SkeletonChart(height: 160)
                } else {
                    ServerChart(title: "CPU", points: points, value: \.cpu, color: Vivid.indigo, limit: 80)
                    ServerChart(title: "RAM", points: points, value: \.ram, color: Vivid.teal, limit: 85)
                    ServerChart(title: "Disk", points: points, value: \.disk, color: Vivid.orange, limit: 90)
                }
            }
        }
    }

    // MARK: - Processes

    private var processesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionHeader(title: "Top processes", symbol: "cpu", tint: Vivid.blue)
                Picker("Sort", selection: $byMemory) {
                    Text("CPU").tag(false)
                    Text("Memory").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .controlSize(.small)
                Button { Task { await loadProcesses() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Reload processes")
            }
            if processes.isEmpty {
                LoadingOrEmptyRow(isLoading: !loaded, text: "No process list from this server", symbol: "cpu")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(processes.enumerated()), id: \.element.id) { index, process in
                        if index > 0 { Divider() }
                        HStack(spacing: 10) {
                            Text(process.name).font(.system(size: 12, design: .monospaced)).lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .help(process.cmd ?? process.name)
                            Text(process.user ?? "").font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 80, alignment: .leading)
                            Text(String(format: "%.1f%%", process.cpu)).frame(width: 60, alignment: .trailing)
                            Text(Bytes.string(process.rss)).foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
                        }
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                    }
                }
                .card()
            }
        }
    }

    // MARK: - Services

    private func servicesCard(_ status: ServerStatus) -> some View {
        let services = (inventory?.services ?? []).sorted { ($0.isFailed ? 0 : 1, $0.name) < ($1.isFailed ? 0 : 1, $1.name) }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionHeader(title: "Services", symbol: "gearshape.2.fill", tint: Vivid.teal)
                Spacer()
                if let at = inventoryAt {
                    Text("as of \(RelativeTime.ago(at))").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            if services.isEmpty {
                LoadingOrEmptyRow(isLoading: !loaded, text: "No service list from this server", symbol: "gearshape.2")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(services.enumerated()), id: \.element.id) { index, service in
                        if index > 0 { Divider() }
                        HStack(spacing: 10) {
                            Circle()
                                .fill(service.isFailed ? Color.statusDanger : (service.isRunning ? Color.statusSuccess : Color.secondary))
                                .frame(width: 8, height: 8)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(service.name).font(.system(size: 12, design: .monospaced))
                                if let description = service.description {
                                    Text(description).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Text([service.active, service.sub].compactMap { $0 }.joined(separator: " · "))
                                .font(.system(size: 11))
                                .foregroundStyle(service.isFailed ? Color.statusDangerText : .secondary)
                            PopUpMenuButton(label: "Actions for \(service.name)") {
                                let menu = NSMenu(title: service.name)
                                for verb in FleetAction.ServiceVerb.allCases {
                                    menu.addItem(ClosureMenuItem(verb == .stop ? "Stop…  (Touch ID)" : "\(verb.rawValue.capitalized)…") {
                                        let id = serverID, name = status.server.name
                                        Task {
                                            if await executor.runFleetAction(serverID: id, serverName: name, .service(verb, name: service.name)) {
                                                reloadSoon()
                                            }
                                        }
                                    })
                                }
                                return menu
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .accessibilityElement(children: .contain)
                    }
                }
                .card()
            }
        }
    }

    // MARK: - Side cards

    private func alertsCard(_ status: ServerStatus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Open alerts", symbol: "bell.badge.fill", tint: Vivid.orange)
            if status.alerts.isEmpty {
                EmptyRow(text: "No open alerts", symbol: "checkmark.circle")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(status.alerts.enumerated()), id: \.element.id) { index, alert in
                        if index > 0 { Divider() }
                        HStack(spacing: 10) {
                            StatusMarkView(mark: FleetAlertKind.isCritical(kind: alert.kind) ? .failure : .warning, size: 14)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(FleetAlertKind.headline(kind: alert.kind, value: alert.value, message: alert.message))
                                    .font(.system(size: 12, weight: .medium))
                                Text("since \(RelativeTime.ago(alert.startedAt))").font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                    }
                }
                .card(tint: .tintWarning)
            }
        }
    }

    private var forecastCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Disks", symbol: "internaldrive.fill", tint: Vivid.orange)
            VStack(alignment: .leading, spacing: 10) {
                if forecast.isEmpty {
                    if loaded {
                        Text("No disk data.").font(.system(size: 12)).foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 8) { SkeletonBar(height: 9); SkeletonBar(width: 120, height: 7) }.shimmering()
                    }
                }
                ForEach(forecast) { mount in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(mount.mount).font(.system(size: 12, design: .monospaced))
                            Spacer()
                            Text("\(Int(mount.usedPct.rounded()))%").font(.system(size: 12)).monospacedDigit()
                        }
                        ProgressBar(fraction: mount.usedPct / 100,
                                    tint: mount.usedPct >= 90 ? .statusDanger : (mount.usedPct >= 80 ? .statusWarning : .accentColor), height: 6)
                        if let days = mount.daysLeft {
                            Text(days < 60 ? "Full in about \(Int(days.rounded())) days at the current rate" : "Not filling up soon")
                                .font(.system(size: 11))
                                .foregroundStyle(days < 14 ? Color.statusWarningText : .secondary)
                        }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    @ViewBuilder
    private func updatesCard(_ status: ServerStatus) -> some View {
        if let updates = inventory?.updates {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Package updates", symbol: "shippingbox.fill", tint: Vivid.purple)
                VStack(alignment: .leading, spacing: 8) {
                    Text(updates.count == 0 ? "Up to date" : "\(updates.count) packages · \(updates.security) security")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(updates.security > 0 ? Color.statusWarningText : .primary)
                    if updates.rebootRequired {
                        Label("A reboot is required", systemImage: "arrow.clockwise").font(.system(size: 12)).foregroundStyle(Color.statusWarningText)
                    }
                    ForEach(updates.packages.prefix(6)) { package in
                        HStack {
                            Text(package.name).font(.system(size: 11, design: .monospaced))
                            if package.security { Tag(text: "Security", tint: .statusWarningText) }
                            Spacer()
                            Text(package.available ?? "").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                    if updates.count > 0 {
                        Button("Update Packages…") {
                            let id = serverID, name = status.server.name
                            Task { if await executor.runFleetAction(serverID: id, serverName: name, .updatePackages(distUpgrade: false)) { reloadSoon() } }
                        }
                        .controlSize(.small)
                        .help("Runs apt upgrade; asks for confirmation and Touch ID")
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
            }
        }
    }

    @ViewBuilder
    private func containersCard(_ status: ServerStatus) -> some View {
        if let docker = inventory?.docker, docker.available, !docker.containers.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Containers", symbol: "shippingbox", tint: Vivid.blue)
                VStack(spacing: 0) {
                    ForEach(Array(docker.containers.enumerated()), id: \.element.id) { index, container in
                        if index > 0 { Divider() }
                        HStack(spacing: 8) {
                            Circle().fill(container.state == "running" ? Color.statusSuccess : Color.statusWarning)
                                .frame(width: 8, height: 8).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(container.name).font(.system(size: 12, design: .monospaced))
                                Text(container.status ?? container.state).font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            PopUpMenuButton(label: "Actions for \(container.name)") {
                                let menu = NSMenu(title: container.name)
                                for verb in FleetAction.ContainerVerb.allCases {
                                    menu.addItem(ClosureMenuItem(verb == .stop ? "Stop…  (Touch ID)" : "\(verb.rawValue.capitalized)…") {
                                        let id = serverID, name = status.server.name
                                        Task {
                                            if await executor.runFleetAction(serverID: id, serverName: name,
                                                                             .container(verb, id: container.id, name: container.name)) { reloadSoon() }
                                        }
                                    })
                                }
                                return menu
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                }
                .card()
            }
        }
    }
}

/// One metric over the chosen range, with its alert threshold dashed.
private struct ServerChart: View {
    var title: String
    var points: [FleetMetricsHistory.Point]
    var value: KeyPath<FleetMetricsHistory.Point, Double>
    var color: Color
    var limit: Double

    var body: some View {
        let now: Double = points.last.map { $0[keyPath: value] } ?? 0
        let peak: Double = points.map { $0[keyPath: value] }.max() ?? 0
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(points.isEmpty ? "—" : "\(Int(now.rounded()))%").fontWeight(.semibold).foregroundStyle(.primary).monospacedDigit()
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            InteractiveLineChart(
                series: [ChartSeries(name: title, color: color,
                                     points: points.map { SeriesPoint(date: $0.t, value: $0[keyPath: value]) })],
                unit: .percent, yDomain: 0...100, threshold: limit, style: .card)
                .frame(height: 110)
            Text(points.isEmpty ? "No samples in this range" : "peak \(Int(peak.rounded()))% · dashed line \(Int(limit))%")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

/// A shell on the server: needs its "web terminal" switch, the password session and a
/// 2FA step-up, exactly as the panel's own server terminal.
struct ServerTerminalSection: View {
    let environment: AppEnvironment
    var server: FleetServer

    private var admin: AdminAccess { environment.admin }

    var body: some View {
        if !server.terminalEnabled {
            ContentUnavailableView {
                Label("The terminal is off for \(server.name)", systemImage: "lock.slash")
            } description: {
                Text("Turn on “Web terminal” in this server’s settings in the web panel. Turning it on also needs a 2FA code there.")
            } actions: {
                Button("Open Server in Web Panel") { WebPanel.open(.server(id: server.id)) }
            }
        } else if admin.isElevated() {
            TerminalPane(title: server.name,
                         warning: "You are on the server itself; commands run as its login user.",
                         makeURL: { admin.serverTerminalURL(serverID: server.id, cols: 120, rows: 32) })
                .id(server.id)
        } else {
            TerminalLocked(title: "Terminal for \(server.name)",
                           detail: "A server shell needs your password and a fresh 2FA code. The code unlocks terminals and scripts for 15 minutes in this app.",
                           buttonTitle: admin.isSignedIn ? "Confirm with 2FA…" : "Sign In…") {
                let admin = self.admin, email = environment.session.user?.email
                Task { _ = await AdminPrompt.ensureElevated(admin, suggestedEmail: email) }
            }
        }
    }
}
