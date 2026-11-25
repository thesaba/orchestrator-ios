import SwiftUI

/// Signed out: a short explanation and Sign in.
struct SignedOutView: View {
    var signIn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sign in with a personal access token to watch your servers, sites and deploys from the menu bar.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Sign In…", action: signIn)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .card()
    }
}

/// First load: grey placeholders in the shape of the overview, no invented values.
struct LoadingPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(0..<2, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 3).fill(.fill.tertiary).frame(width: 70, height: 9)
                    VStack(spacing: 0) {
                        ForEach(0..<3, id: \.self) { index in
                            if index > 0 { Divider() }
                            HStack(spacing: 10) {
                                Circle().fill(.fill.tertiary).frame(width: 8, height: 8).padding(.horizontal, 4)
                                VStack(alignment: .leading, spacing: 4) {
                                    RoundedRectangle(cornerRadius: 3).fill(.fill.tertiary).frame(width: 120, height: 10)
                                    RoundedRectangle(cornerRadius: 3).fill(.fill.quaternary).frame(width: 90, height: 8)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                        }
                    }
                    .card()
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Loading")
    }
}

/// "No servers", "No open alerts" inside a card.
struct EmptyRow: View {
    var text: String
    var symbol: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(.secondary)
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .card()
        .accessibilityElement(children: .combine)
    }
}
