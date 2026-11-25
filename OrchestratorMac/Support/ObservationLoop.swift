import Foundation
import Observation

/// Calls `onChange` every time a value read in `track` changes, for as long as the loop is
/// retained. A thin wrapper around `withObservationTracking`, which only fires once.
@MainActor
final class ObservationLoop {
    private let track: @MainActor () -> Void
    private let onChange: @MainActor () -> Void
    private var isActive = true

    init(track: @escaping @MainActor () -> Void, onChange: @escaping @MainActor () -> Void) {
        self.track = track
        self.onChange = onChange
        register()
    }

    func cancel() { isActive = false }

    private func register() {
        guard isActive else { return }
        withObservationTracking {
            track()
        } onChange: { [weak self] in
            // `onChange` runs before the new value is stored; hop to the next turn.
            Task { @MainActor [weak self] in
                guard let self, self.isActive else { return }
                self.onChange()
                self.register()
            }
        }
    }
}
