import AppKit
import OrchestratorKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var environment: AppEnvironment?
    /// Links that arrive before the environment exists (the app was launched by one).
    private var pendingLinks: [DeepLink] = []

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Load the icon from the asset catalog, not the system icon cache: alerts and other
        // in-app surfaces then show the Orchestrator logo even when that cache is stale.
        if let icon = NSImage(named: "AppIcon") {
            NSApp.applicationIconImage = icon
        }

        // An Apple Event handler, so `orchestrator://` links reach the app directly instead of
        // SwiftUI's scene handling (which would try to open a window for them).
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleURLEvent(_:replyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let environment = AppEnvironment()
        self.environment = environment
        environment.start()
        pendingLinks.forEach(environment.open)
        pendingLinks.removeAll()
    }

    func applicationWillTerminate(_ notification: Notification) {
        environment?.stop()
    }

    @objc private func handleURLEvent(_ event: NSAppleEventDescriptor, replyEvent: NSAppleEventDescriptor) {
        guard let text = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: text), let link = DeepLink(url: url) else { return }
        if let environment {
            environment.open(link)
        } else {
            pendingLinks.append(link)
        }
    }
}
