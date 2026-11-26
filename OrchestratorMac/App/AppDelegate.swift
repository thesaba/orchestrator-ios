import AppKit
import OrchestratorKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set only by "Quit Orchestrator" in the menu bar item's menu. Every other quit (the
    /// Dock's Quit, ⌘Q) closes the windows and leaves the app running in the menu bar.
    static var allowsTermination = false

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

    /// Clicking the Dock icon with no window open brings the main window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { environment?.windows.showMain() }
        return true
    }

    /// Closing the window keeps the app running in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if Self.allowsTermination || Self.isSystemQuit { return .terminateNow }
        Self.retreatToMenuBar()
        return .terminateCancel
    }

    /// Log out, restart and shut down send the quit event with a reason; those always quit.
    private static var isSystemQuit: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventClass == AEEventClass(kCoreEventClass),
              event.eventID == AEEventID(kAEQuitApplication) else { return false }
        return event.attributeDescriptor(forKeyword: AEKeyword(kAEQuitReason)) != nil
    }

    /// Closes the app's windows and drops the Dock icon; the menu bar item stays.
    static func retreatToMenuBar() {
        for window in NSApp.windows where window.isVisible && window.styleMask.contains(.titled) {
            window.close()
        }
        NSApp.setActivationPolicy(.accessory)
    }

    /// The real quit, from the menu bar item's menu.
    static func quitCompletely() {
        allowsTermination = true
        NSApp.terminate(nil)
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
