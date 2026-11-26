import AppKit
import SwiftUI

/// The main window: sidebar, toolbar search and the selected section.
///
/// Tracks whether the window is actually on screen, so polling speeds up only while someone
/// can see it and the window's extra data stops loading when it is closed or minimised.
@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate {
    let model: MainWindowModel
    private weak var environment: AppEnvironment?
    private var occlusionObserver: NSObjectProtocol?

    init(environment: AppEnvironment) {
        self.environment = environment
        model = MainWindowModel(data: MainDataStore(store: environment.store, api: environment.api))

        let host = NSHostingController(rootView: MainView(environment: environment, model: model))
        // Fixed initial size: the split view must not drive the window through its preferred size.
        host.sizingOptions = []
        host.sceneBridgingOptions = [.toolbars, .title]

        let window = NSWindow(contentViewController: host)
        window.title = "Orchestrator"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 1280, height: 820))
        window.contentMinSize = NSSize(width: 900, height: 600)
        window.setFrameAutosaveName("MainWindow")
        if window.frame.origin == .zero { window.center() }
        super.init(window: window)
        window.delegate = self

        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateVisibility() }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show() {
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        updateVisibility()
    }

    func windowWillClose(_ notification: Notification) {
        setVisible(false)
    }

    private func updateVisibility() {
        guard let window else { return }
        setVisible(window.isVisible && window.occlusionState.contains(.visible))
    }

    private func setVisible(_ visible: Bool) {
        model.data.isVisible = visible
        environment?.scheduler.isMainWindowVisible = visible
    }
}
