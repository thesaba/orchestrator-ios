import SwiftUI

struct RootView: View {
    @Environment(Session.self) private var session
    @Environment(AppLock.self) private var appLock
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch session.phase {
            case .launching:
                LaunchView()
            case .signedOut:
                LoginView()
                    .transition(.opacity)
            case .signedIn:
                if appLock.needsFirstUnlock {
                    // Cold launch behind the lock: do not construct the tab hierarchy yet,
                    // or its `.task` modifiers fire with no bearer and cache a 401.
                    LockScreenView()
                        .transition(.opacity)
                } else {
                    MainTabView()
                        .transition(.opacity)
                }
            }
        }
        .animation(.default, value: session.phase)
        .overlay {
            // A re-lock covers the running app instead of tearing it down, so the user
            // keeps their place — and an in-flight deploy stream keeps its log.
            if session.phase == .signedIn && appLock.state != .unlocked && appLock.hasUnlockedOnce {
                LockScreenView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appLock.state)
        .task {
            if session.phase == .launching {
                await session.bootstrap()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            appLock.handleScenePhase(phase)
        }
        .onChange(of: session.phase) { _, phase in
            // Any sign-out path must also drop the lock, or the next sign-in would be
            // stuck behind a gate protecting a token that no longer exists.
            if phase == .signedOut { appLock.reset() }
        }
        .onChange(of: appLock.state) { _, state in
            // Cold launch with the lock on skips `/auth/me` (no bearer available yet),
            // so fetch the account once the token is readable.
            if state == .unlocked { Task { await session.refreshUserIfNeeded() } }
        }
    }
}

private struct LaunchView: View {
    var body: some View {
        VStack(spacing: 16) {
            OrchestratorLogo(size: 72)
            ProgressView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}
