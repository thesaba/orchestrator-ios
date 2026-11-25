import AppKit
import OrchestratorKit
import SwiftUI

/// The floating, non-activating palette panel: opens on the global shortcut, centred
/// horizontally in the upper third of the screen under the pointer, closes on Escape and
/// when it loses focus.
@MainActor
final class PaletteController: NSObject, NSWindowDelegate {
    private let environment: AppEnvironment
    private let model: PaletteModel
    private let hotKey = GlobalHotKey()
    private var panel: PalettePanel?
    private var keyMonitor: Any?
    private var contentHeight: CGFloat = 200

    init(environment: AppEnvironment) {
        self.environment = environment
        self.model = PaletteModel(environment: environment)
        super.init()
        model.closeAndRun = { [weak self] work in
            self?.close()
            Task { @MainActor in await work() }
        }
    }

    // MARK: - Shortcut

    /// Registers the shortcut from settings. Returns false when the system refuses it.
    @discardableResult
    func registerShortcut() -> Bool {
        hotKey.register(environment.settings.paletteShortcut) { [weak self] in self?.toggle() }
    }

    func suspendShortcut(_ suspended: Bool) {
        if suspended { hotKey.unregister() } else { registerShortcut() }
    }

    // MARK: - Showing

    var isShown: Bool { panel?.isVisible ?? false }

    func toggle() {
        isShown ? close() : show()
    }

    func show() {
        guard environment.session.phase == .signedIn else {
            environment.windows.showSignIn()
            return
        }
        model.reset()
        let panel = self.panel ?? makePanel()
        self.panel = panel
        position(panel)
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    func close() {
        removeKeyMonitor()
        panel?.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    // MARK: - Panel

    private func makePanel() -> PalettePanel {
        let panel = PalettePanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: contentHeight),
                                 styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                                 backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.setAccessibilityLabel("Command palette")

        let view = PaletteView(model: model) { [weak self] height in
            self?.updateHeight(height)
        }
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = []
        panel.contentView = hosting
        return panel
    }

    private func position(_ panel: PalettePanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let top = visible.maxY - visible.height * 0.18
        let origin = NSPoint(x: visible.midX - 320, y: top - contentHeight)
        panel.setFrame(NSRect(origin: origin, size: NSSize(width: 640, height: contentHeight)), display: true)
    }

    /// Grows and shrinks downwards, keeping the field where it is.
    private func updateHeight(_ height: CGFloat) {
        guard height > 0, abs(height - contentHeight) > 0.5 else { return }
        contentHeight = height
        guard let panel else { return }
        var frame = panel.frame
        let top = frame.maxY
        frame.size.height = height
        frame.origin.y = top - height
        panel.setFrame(frame, display: true)
    }

    // MARK: - Keys

    /// Arrow keys, Return variants and Escape are handled here; everything else types.
    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let panel = self.panel, event.window === panel else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            switch event.keyCode {
            case 53: // Escape
                if !self.model.back() { self.close() }
                return nil
            case 125: // Down
                self.model.moveSelection(1)
                return nil
            case 126: // Up
                self.model.moveSelection(-1)
                return nil
            case 36, 76: // Return, Enter
                if flags.contains(.command) {
                    self.model.activate(.runAndShowLog)
                } else if flags.contains(.option) {
                    self.model.activate(.chooseBranch)
                } else {
                    self.model.activate(.run)
                }
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}

/// A borderless panel that can take keyboard focus without activating the app.
final class PalettePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
