import SwiftUI

/// A regular Dock app with a main window, plus the menu bar item. `AppDelegate` builds the
/// environment; windows are managed by `WindowCoordinator` so the status item, notifications
/// and deep links can open them too.
@main
struct OrchestratorMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Required by `App`. The real settings window is opened by `WindowCoordinator`.
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { AppEnvironment.current?.windows.showSettings() }
                    .keyboardShortcut(",")
            }
            CommandGroup(replacing: .newItem) {}
            // ⌘Q keeps monitoring in the menu bar; quitting for good is in the menu bar item's menu.
            CommandGroup(replacing: .appTermination) {
                Button("Close to Menu Bar") { AppDelegate.retreatToMenuBar() }
                    .keyboardShortcut("q")
            }
            CommandGroup(before: .windowList) {
                Button("Orchestrator") { AppEnvironment.current?.windows.showMain() }
                    .keyboardShortcut("0")
                Divider()
            }
        }
    }
}
