import SwiftUI

/// Agent app (`LSUIElement`): no Dock icon, no main window. Everything starts from the
/// status item that `AppDelegate` installs; windows are managed by `WindowCoordinator`.
@main
struct OrchestratorMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Required by `App`; the real settings window is opened by `WindowCoordinator`
        // so it can be shown from the popover and from notifications alike.
        Settings {
            EmptyView()
        }
    }
}
