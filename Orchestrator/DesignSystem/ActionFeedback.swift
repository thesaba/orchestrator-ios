import SwiftUI
import OrchestratorKit

/// Success / failure strip shown under an action bar. Auto-clears the success note.
struct ActionFeedbackView: View {
    @Bindable var runner: ActionRunner

    var body: some View {
        VStack(spacing: 8) {
            if let error = runner.errorMessage {
                InlineErrorBanner(message: error) { runner.errorMessage = nil }
            }
            if let success = runner.successMessage {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(success)
                        .font(.footnote)
                    Spacer()
                }
                .padding(10)
                .background(Color.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                .task {
                    try? await Task.sleep(for: .seconds(4))
                    if runner.successMessage == success { runner.successMessage = nil }
                }
            }
        }
    }
}

/// A row that launches a server-changing action, with a spinner while it runs.
struct ActionRow: View {
    var title: String
    var subtitle: String?
    var systemImage: String
    var role: ButtonRole?
    var isBusy: Bool = false
    var isDisabled: Bool = false
    var action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isBusy { ProgressView().controlSize(.small) }
            }
        }
        .disabled(isDisabled || isBusy)
    }
}
