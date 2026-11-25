import AppKit
import OrchestratorKit

/// Right-click menus of popover rows, built at click time (see `RightClickMenu`).
/// Items that change production go through `CommandExecutor`, so each confirms first and
/// asks for Touch ID where required.
@MainActor
enum RowMenus {
    static func site(_ site: SiteStatus, environment: AppEnvironment) -> NSMenu {
        let executor = environment.executor
        let siteID = site.id
        let listing = environment.store.siteListings?.first { $0.id == siteID }
        let menu = NSMenu(title: site.domain)

        menu.addItem(ClosureMenuItem("Deploy…", symbol: "arrow.up") {
            Task { await executor.deploy(siteID: siteID, ref: nil) }
        })
        menu.addItem(ClosureMenuItem("Deploy Branch, Tag or Commit…", symbol: "arrow.triangle.branch") {
            Task { await executor.deployChoosingRef(siteID: siteID) }
        })
        menu.addItem(ClosureMenuItem("Roll Back…  (Touch ID)", symbol: "arrow.uturn.backward") {
            Task { await executor.rollback(siteID: siteID) }
        })
        menu.addItem(.separator())

        if listing?.maintenanceMode == true {
            menu.addItem(ClosureMenuItem("Turn Off Maintenance Mode…  (Touch ID)", symbol: "checkmark.circle") {
                Task { await executor.setMaintenance(siteID: siteID, enable: false) }
            })
        } else {
            menu.addItem(ClosureMenuItem("Turn On Maintenance Mode…  (Touch ID)", symbol: "exclamationmark.triangle") {
                Task { await executor.setMaintenance(siteID: siteID, enable: true) }
            })
        }
        menu.addItem(ClosureMenuItem("Clear Cache…", symbol: "trash") {
            Task { await executor.runArtisan(siteID: siteID, command: "optimize:clear") }
        })
        menu.addItem(ClosureMenuItem("Restart Queue…", symbol: "arrow.clockwise") {
            Task { await executor.runArtisan(siteID: siteID, command: "queue:restart") }
        })
        menu.addItem(artisanItem(siteID: siteID, environment: environment))
        if listing?.sslEnabled == true {
            menu.addItem(ClosureMenuItem("Renew SSL…", symbol: "lock.rotation") {
                Task { await executor.renewCertificate(siteID: siteID) }
            })
        }
        menu.addItem(.separator())

        menu.addItem(ClosureMenuItem("Deploy Log", symbol: "text.alignleft") {
            environment.open(.deployLog(siteID: siteID))
        })
        menu.addItem(ClosureMenuItem("Site Logs", symbol: "doc.text.magnifyingglass") {
            environment.open(.siteLogs(siteID: siteID))
        })
        menu.addItem(ClosureMenuItem("Open in Web Panel", symbol: "safari") {
            WebPanel.open(.site(id: siteID))
        })
        return menu
    }

    static func server(_ server: FleetServer, environment: AppEnvironment) -> NSMenu {
        let executor = environment.executor
        let serverID = server.id
        let menu = NSMenu(title: server.name)
        if server.isLocal || server.hasSsh || server.host != nil {
            menu.addItem(ClosureMenuItem("SSH into \(server.name)", symbol: "apple.terminal") {
                Task { await executor.openSSH(serverID: serverID) }
            })
        }
        menu.addItem(ClosureMenuItem("Open in Web Panel", symbol: "safari") {
            WebPanel.open(.server(id: serverID))
        })
        return menu
    }

    private static func artisanItem(siteID: Int, environment: AppEnvironment) -> NSMenuItem {
        let item = NSMenuItem(title: "Run Artisan Command", action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "chevron.left.forwardslash.chevron.right", accessibilityDescription: nil)
        let submenu = NSMenu(title: "Run Artisan Command")
        let commands = environment.artisanCatalog.commands
        if commands.isEmpty {
            let placeholder = NSMenuItem(title: environment.artisanCatalog.isLoading ? "Loading…" : "Unavailable",
                                         action: nil, keyEquivalent: "")
            placeholder.isEnabled = false
            submenu.addItem(placeholder)
            environment.artisanCatalog.loadIfNeeded(siteID: siteID, api: environment.api)
        }
        let executor = environment.executor
        for command in commands {
            let title = ArtisanSafety.needsAuthentication(command.cmd) ? "\(command.cmd)…  (Touch ID)" : "\(command.cmd)…"
            let entry = ClosureMenuItem(title) {
                Task { await executor.runArtisan(siteID: siteID, command: command.cmd) }
            }
            entry.toolTip = command.description
            submenu.addItem(entry)
        }
        item.submenu = submenu
        return item
    }
}

/// The Artisan commands the panel allows (the same list for every site), loaded once.
@MainActor
@Observable
final class ArtisanCatalog {
    private(set) var commands: [ArtisanCommand] = []
    private(set) var isLoading = false

    /// GET only; called when the popover opens and the list is still empty.
    func loadIfNeeded(siteID: Int?, api: OrchestratorAPI) {
        guard commands.isEmpty, !isLoading, let siteID else { return }
        isLoading = true
        Task {
            defer { isLoading = false }
            commands = ((try? await api.artisanCommands(siteID: siteID)) ?? []).sorted { $0.cmd < $1.cmd }
        }
    }
}
