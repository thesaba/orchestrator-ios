import AppKit

/// A borderless panel that can take keyboard focus without activating the app, so its
/// buttons and checkboxes work while another app stays in front.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
