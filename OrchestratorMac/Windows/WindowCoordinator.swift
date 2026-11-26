import AppKit
import SwiftUI

/// Opens and reuses the app's windows: the main window, Settings, Sign In and site logs.
@MainActor
final class WindowCoordinator {
    weak var environment: AppEnvironment?

    private(set) var main: MainWindowController?
    private var settingsWindow: NSWindow?
    private var signInWindow: NSWindow?
    private var siteLogWindows: [Int: NSWindow] = [:]

    func showMain() {
        guard let environment else { return }
        let controller = main ?? MainWindowController(environment: environment)
        main = controller
        controller.show()
    }

    func showSettings() {
        guard let environment else { return }
        let window = settingsWindow ?? makeWindow(
            title: "Orchestrator Settings",
            content: SettingsView(environment: environment),
            autosaveName: "SettingsWindow",
            size: SettingsView.size
        )
        settingsWindow = window
        present(window)
    }

    func showSignIn() {
        guard let environment else { return }
        let window = signInWindow ?? makeWindow(
            title: "Sign In to Orchestrator",
            content: SignInView(session: environment.session),
            autosaveName: "SignInWindow"
        )
        signInWindow = window
        present(window)
    }

    func closeSignIn() {
        signInWindow?.close()
    }

    func showSiteLogs(siteID: Int, domain: String) {
        guard let environment else { return }
        let window = siteLogWindows[siteID] ?? makeWindow(
            title: "\(domain) — Site log",
            content: SiteLogsView(siteID: siteID, domain: domain, api: environment.api),
            autosaveName: "SiteLogsWindow",
            size: NSSize(width: 760, height: 520),
            resizable: true
        )
        siteLogWindows[siteID] = window
        present(window)
    }

    private func present(_ window: NSWindow) {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// - Parameter size: a fixed content size. Views with scrolling content (forms, tab views,
    ///   lists) need one: letting them drive the window through `preferredContentSize` makes
    ///   AppKit loop on constraint passes and throw. Without it the window fits the view.
    private func makeWindow(title: String, content: some View, autosaveName: String,
                            size: NSSize? = nil, resizable: Bool = false) -> NSWindow {
        let controller = NSHostingController(rootView: content)
        controller.sizingOptions = size == nil ? [.preferredContentSize] : []
        let window = NSWindow(contentViewController: controller)
        window.title = title
        window.styleMask = resizable ? [.titled, .closable, .resizable] : [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName(autosaveName)
        if let size {
            // After the autosave name, which restores an older saved frame.
            if !resizable || window.frame.width < size.width * 0.75 { window.setContentSize(size) }
            window.contentMinSize = resizable ? NSSize(width: size.width * 0.75, height: size.height * 0.75) : size
        }
        window.center()
        return window
    }
}
