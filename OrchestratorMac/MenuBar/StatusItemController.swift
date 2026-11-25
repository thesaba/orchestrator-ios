import AppKit
import SwiftUI

/// The menu bar item and its popover.
///
/// `NSStatusItem` + `NSPopover` rather than `MenuBarExtra`, because notifications, widgets
/// and the palette need to open the popover programmatically on a given segment.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let environment: AppEnvironment
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let popoverState = PopoverState()
    private var labelObservation: ObservationLoop?

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init()
        configureButton()
        configurePopover()
    }

    // MARK: - Popover

    func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover(segment: nil)
        }
    }

    func closePopover() {
        popover.performClose(nil)
    }

    /// Opens the popover, optionally on a specific segment.
    func showPopover(segment: PopoverSegment?) {
        if let segment { popoverState.segment = segment }
        guard let button = statusItem.button else { return }
        if !popover.isShown {
            NSApp.activate()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func popoverWillShow(_ notification: Notification) {
        environment.scheduler.isPopoverOpen = true
    }

    func popoverDidClose(_ notification: Notification) {
        environment.scheduler.isPopoverOpen = false
        popoverState.segment = .overview
    }

    // MARK: - Setup

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let label = StatusItemLabel(environment: environment) { [weak self] width in
            self?.statusItem.length = max(24, ceil(width))
        }
        let hosting = PassthroughHostingView(rootView: label)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: button.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: button.bottomAnchor)
        ])

        labelObservation = ObservationLoop { [weak self] in
            guard let self else { return }
            button.setAccessibilityLabel(StatusItemState(environment: self.environment).accessibilityLabel)
        } onChange: {}
    }

    private func configurePopover() {
        let controller = NSHostingController(rootView: PopoverView(environment: environment, state: popoverState))
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
    }

    @objc private func statusItemClicked() {
        togglePopover()
    }
}

/// Hosts the SwiftUI label inside the status item button without swallowing its clicks.
private final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
