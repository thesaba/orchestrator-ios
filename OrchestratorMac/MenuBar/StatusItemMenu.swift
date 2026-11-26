import AppKit
import OrchestratorKit

/// The menu bar icon's right-click menu, built at click time so a refresh cannot change it
/// while it is open. Actions that change production go through `CommandExecutor` and confirm.
@MainActor
enum StatusItemMenu {
    static func build(environment: AppEnvironment) -> NSMenu {
        let menu = NSMenu(title: "Orchestrator")
        menu.autoenablesItems = false
        let signedIn = environment.session.phase == .signedIn

        menu.addItem(statusLine(environment: environment, signedIn: signedIn))
        menu.addItem(.separator())

        if signedIn {
            addMonitoringItems(to: menu, environment: environment)
            menu.addItem(.separator())
            addSiteItems(to: menu, environment: environment)
            menu.addItem(.separator())
            addNotificationItems(to: menu, environment: environment)
            menu.addItem(.separator())
        } else {
            menu.addItem(ClosureMenuItem("Sign In…", symbol: "person.crop.circle") { environment.windows.showSignIn() })
            menu.addItem(.separator())
        }

        addAppItems(to: menu, environment: environment, signedIn: signedIn)
        return menu
    }

    // MARK: - Status

    private static func statusLine(environment: AppEnvironment, signedIn: Bool) -> NSMenuItem {
        let store = environment.store
        var parts: [String]
        if !signedIn {
            parts = ["Signed out"]
        } else if environment.scheduler.isPaused {
            parts = ["Monitoring paused"]
        } else if !store.hasLoaded {
            parts = ["Loading…"]
        } else {
            parts = [store.overview.summary]
            if store.overview.isDeploying { parts.append("\(store.overview.siteCounts.deploying) deploying") }
            if let error = store.lastError {
                parts.append(error)
            } else if let updated = store.lastUpdated {
                parts.append("updated \(RelativeTime.ago(updated))")
            }
        }
        let item = NSMenuItem(title: parts.joined(separator: " · "), action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // MARK: - Monitoring

    private static func addMonitoringItems(to menu: NSMenu, environment: AppEnvironment) {
        let scheduler = environment.scheduler
        let refresh = ClosureMenuItem("Refresh Now", symbol: "arrow.clockwise") { scheduler.refreshNow() }
        refresh.isEnabled = !scheduler.isPaused
        menu.addItem(refresh)
        if scheduler.isPaused {
            menu.addItem(ClosureMenuItem("Resume Monitoring", symbol: "play.fill") { scheduler.resume() })
        } else {
            menu.addItem(ClosureMenuItem("Pause Monitoring", symbol: "pause.fill") { scheduler.pause() })
        }
        menu.addItem(ClosureMenuItem("Open Alerts", symbol: "exclamationmark.triangle") {
            environment.open(.popover(.alerts))
        })
        menu.addItem(ClosureMenuItem("Open Web Panel", symbol: "safari") { WebPanel.open(.home) })
    }

    // MARK: - Sites, deploys, servers

    private static func addSiteItems(to menu: NSMenu, environment: AppEnvironment) {
        let overview = environment.store.overview

        let live = overview.sites.filter(\.isDeploying)
        menu.addItem(submenu("Live Deploys", symbol: "arrow.up.circle",
                             empty: "No deploys running", items: live.map { site in
            ClosureMenuItem("\(site.domain) — \(site.deploy?.currentStep.map { "step \($0.number) of \($0.total)" } ?? "running")") {
                environment.logs.showLiveDeploy(for: site)
            }
        }))

        let recent = overview.sites
            .filter { $0.lastDeployAt != nil && !$0.isDeploying }
            .sorted { ($0.lastDeployAt ?? .distantPast) > ($1.lastDeployAt ?? .distantPast) }
            .prefix(5)
        menu.addItem(submenu("Recent Deploys", symbol: "clock.arrow.circlepath",
                             empty: environment.store.siteListings == nil ? "Loading…" : "No deploys yet",
                             items: recent.map { site in
            let outcome = site.lastDeployStatus == "success" ? "✓" : "✗"
            let when = site.lastDeployAt.map { RelativeTime.ago($0) } ?? ""
            let item = ClosureMenuItem("\(outcome) \(site.domain) — \(when)") {
                environment.open(.deployLog(siteID: site.id))
            }
            item.toolTip = [site.branch, site.shortCommit, site.lastDeployStatus].compactMap { $0 }.joined(separator: " · ")
            return item
        }))

        let sites = overview.sites.sorted { $0.domain.localizedStandardCompare($1.domain) == .orderedAscending }
        menu.addItem(submenu("Sites", symbol: "globe", empty: "No sites", items: sites.map { site in
            let item = NSMenuItem(title: site.domain, action: nil, keyEquivalent: "")
            item.image = markImage(site.mark)
            item.submenu = RowMenus.site(site, environment: environment)
            return item
        }))

        let servers = overview.servers.sorted { $0.server.name.localizedStandardCompare($1.server.name) == .orderedAscending }
        menu.addItem(submenu("Servers", symbol: "server.rack", empty: "No servers", items: servers.map { status in
            let item = NSMenuItem(title: status.server.name, action: nil, keyEquivalent: "")
            item.image = markImage(status.mark)
            item.submenu = RowMenus.server(status.server, environment: environment)
            return item
        }))
    }

    // MARK: - Notifications

    private static func addNotificationItems(to menu: NSMenu, environment: AppEnvironment) {
        let notifications = environment.notifications
        let snooze = NSMenuItem(title: "Snooze Notifications", action: nil, keyEquivalent: "")
        snooze.image = NSImage(systemSymbolName: "bell.slash", accessibilityDescription: nil)
        let options = NSMenu(title: "Snooze Notifications")
        if let until = notifications.snoozedUntil {
            let state = NSMenuItem(title: "Snoozed until \(until.formatted(date: .omitted, time: .shortened))",
                                   action: nil, keyEquivalent: "")
            state.isEnabled = false
            options.addItem(state)
            options.addItem(ClosureMenuItem("Resume Notifications") { notifications.resumeAll() })
            options.addItem(.separator())
        }
        options.addItem(ClosureMenuItem("For 1 Hour") { notifications.snoozeAll(until: .now.addingTimeInterval(3_600)) })
        options.addItem(ClosureMenuItem("Until Tomorrow Morning") { notifications.snoozeAllUntilTomorrow() })
        snooze.submenu = options
        menu.addItem(snooze)

        menu.addItem(ClosureMenuItem("Copy Status Summary", symbol: "doc.on.doc") {
            let store = environment.store
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(FleetStatusIntent.summary(store.overview, error: store.lastError), forType: .string)
        })
    }

    // MARK: - App

    private static func addAppItems(to menu: NSMenu, environment: AppEnvironment, signedIn: Bool) {
        menu.addItem(ClosureMenuItem("Open Orchestrator", symbol: "macwindow") { environment.windows.showMain() })
        menu.addItem(ClosureMenuItem("Settings…", symbol: "gearshape") { environment.windows.showSettings() })

        let launchAtLogin = LaunchAtLogin()
        let login = ClosureMenuItem("Open at Login") { launchAtLogin.set(!launchAtLogin.isEnabled) }
        login.state = launchAtLogin.isEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(ClosureMenuItem("About Orchestrator", symbol: "info.circle") { showAbout(environment: environment) })
        if signedIn {
            menu.addItem(ClosureMenuItem("Sign Out…", symbol: "rectangle.portrait.and.arrow.right") {
                confirmSignOut(environment: environment)
            })
        }
        menu.addItem(.separator())
        let quit = ClosureMenuItem("Quit Orchestrator") { AppDelegate.quitCompletely() }
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }

    private static func showAbout(environment: AppEnvironment) {
        NSApp.activate()
        var credits = "Panel: \(APIConfig.baseURL.host() ?? APIConfig.baseURL.absoluteString)"
        if let email = environment.session.user?.email { credits += "\nSigned in as \(email)" }
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Orchestrator",
            .applicationIcon: NSApp.applicationIconImage as Any,
            .credits: NSAttributedString(string: credits, attributes: [
                .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor
            ])
        ])
    }

    private static func confirmSignOut(environment: AppEnvironment) {
        let confirmed = AlertPresenter.confirm(Confirmation(
            title: "Sign out of Orchestrator?",
            consequence: "The token is removed from this Mac's keychain. Nothing changes in the panel.",
            confirmTitle: "Sign Out"
        ))
        if confirmed { environment.signOut() }
    }

    // MARK: - Helpers

    private static func submenu(_ title: String, symbol: String, empty: String, items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        let submenu = NSMenu(title: title)
        if items.isEmpty {
            let placeholder = NSMenuItem(title: empty, action: nil, keyEquivalent: "")
            placeholder.isEnabled = false
            submenu.addItem(placeholder)
        } else {
            items.forEach(submenu.addItem)
        }
        item.submenu = submenu
        return item
    }

    /// Shape-coded mark for site and server items, with its word for VoiceOver.
    private static func markImage(_ mark: HealthMark) -> NSImage? {
        let color: NSColor
        switch mark {
        case .healthy:   color = .systemGreen
        case .warning:   color = .systemOrange
        case .failure:   color = .systemRed
        case .deploying: color = .controlAccentColor
        case .unknown:   color = .secondaryLabelColor
        }
        let configuration = NSImage.SymbolConfiguration(paletteColors: [color])
        return NSImage(systemSymbolName: mark.symbol, accessibilityDescription: mark.accessibilityLabel)?
            .withSymbolConfiguration(configuration)
    }
}
