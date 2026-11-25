import SwiftUI
import OrchestratorKit

@main
struct OrchestratorApp: App {
    @State private var session = Session()
    @State private var appLock = AppLock()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(appLock)
        }
    }
}
