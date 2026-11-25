import SwiftUI
import OrchestratorKit

/// Every screen models its remote data with this, so loading / empty / error are never forgotten.
enum LoadState<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(APIError)

    var value: Value? {
        if case .loaded(let value) = self { return value }
        return nil
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var error: APIError? {
        if case .failed(let error) = self { return error }
        return nil
    }
}

struct LoadingStateView: View {
    var title: String = "Loading…"

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptyStateView: View {
    var icon: String = "tray"
    var title: String
    var message: String?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            if let message { Text(message) }
        }
    }
}

struct ErrorStateView: View {
    var error: APIError
    var retry: (() -> Void)?

    @State private var showsDetail = false

    var body: some View {
        if error.isLocked {
            // Not a failure: the app is covered by the lock screen and the token is sealed.
            ContentUnavailableView {
                Label("Locked", systemImage: "lock.fill")
            } description: {
                Text("Unlock the app to load this screen.")
            }
        } else {
            failureBody
        }
    }

    private var failureBody: some View {
        ContentUnavailableView {
            Label("Something went wrong", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.errorDescription ?? "Unknown error")
        } actions: {
            VStack(spacing: 8) {
                if let retry {
                    Button("Try again", action: retry)
                        .buttonStyle(.borderedProminent)
                }
                if let detail = error.debugDetail {
                    Button(showsDetail ? "Hide details" : "Show details") {
                        showsDetail.toggle()
                    }
                    .font(.footnote)
                    if showsDetail {
                        ScrollView {
                            Text(detail)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 160)
                    }
                }
            }
        }
    }
}

/// Renders the four states of a `LoadState` with one call site.
struct LoadStateView<Value, Content: View>: View {
    var state: LoadState<Value>
    var emptyTitle: String = "Nothing here yet"
    var emptyMessage: String?
    var emptyIcon: String = "tray"
    var isEmpty: (Value) -> Bool = { _ in false }
    var retry: (() -> Void)?
    @ViewBuilder var content: (Value) -> Content

    var body: some View {
        switch state {
        case .idle, .loading:
            LoadingStateView()
        case .failed(let error):
            ErrorStateView(error: error, retry: retry)
        case .loaded(let value):
            if isEmpty(value) {
                EmptyStateView(icon: emptyIcon, title: emptyTitle, message: emptyMessage)
            } else {
                content(value)
            }
        }
    }
}

/// Inline banner for errors that happen while content is already on screen
/// (a refresh failing, an action failing) — never a silent failure.
struct InlineErrorBanner: View {
    var message: String
    var dismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let dismiss {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
    }
}
