import SwiftUI
import OrchestratorKit

/// Covers the whole app while it is locked. Deliberately offers only two ways forward:
/// authenticate, or sign out and start over.
struct LockScreenView: View {
    @Environment(AppLock.self) private var appLock
    @Environment(Session.self) private var session

    @State private var showsSignOutConfirmation = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                OrchestratorLogo(size: 76)

                VStack(spacing: 6) {
                    Text("Orchestrator is locked")
                        .font(.title3.weight(.semibold))
                    Text("Unlock with \(appLock.unlockMethodDescription) to reach your panel.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if let error = appLock.lastError {
                    InlineErrorBanner(message: error)
                        .frame(maxWidth: 360)
                }

                Button {
                    Task { await appLock.unlock() }
                } label: {
                    if appLock.state == .authenticating {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("Unlock", systemImage: appLock.symbol)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: 320)
                .disabled(appLock.state == .authenticating)

                Button("Sign out instead") {
                    showsSignOutConfirmation = true
                }
                .font(.footnote)
            }
            .padding(28)
        }
        .task {
            // Present the system sheet immediately — one tap saved on every launch.
            if appLock.state == .locked && appLock.lastError == nil {
                await appLock.unlock()
            }
        }
        .confirmationDialog("Sign out?", isPresented: $showsSignOutConfirmation, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) {
                appLock.reset()
                session.signOut()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The token is removed from this device's Keychain. You will need to paste it again.")
        }
    }
}
