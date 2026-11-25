import AppKit
import SwiftUI

/// Opens and reuses the app's ordinary windows: Settings and Sign In.
@MainActor
final class WindowCoordinator {
    weak var environment: AppEnvironment?

    private var settingsWindow: NSWindow?
    private var signInWindow: NSWindow?

    func showSettings() {
        guard let environment else { return }
        let window = settingsWindow ?? makeWindow(
            title: "Orchestrator Settings",
            content: SettingsView(environment: environment),
            autosaveName: "SettingsWindow"
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

    private func present(_ window: NSWindow) {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow(title: String, content: some View, autosaveName: String) -> NSWindow {
        let controller = NSHostingController(rootView: content)
        controller.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: controller)
        window.title = title
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName(autosaveName)
        window.center()
        return window
    }
}
