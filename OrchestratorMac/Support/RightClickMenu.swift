import AppKit
import SwiftUI

/// A right-click (or Control-click) menu built with AppKit at the moment of the click.
///
/// Two things closed menus right after they opened, mostly on the first click:
/// - SwiftUI's `.contextMenu` rebuilds an open menu whenever state it reads changes, which
///   a background refresh does. The `NSMenu` here is a snapshot built on demand.
/// - A menu shown inside the click's own event, attached to the row's view, is cancelled
///   when that click also makes the popover key and SwiftUI redraws the row (button
///   highlight, tooltip). So the menu opens on the next run-loop turn, attached to the
///   window's content view, which lives as long as the popover.
struct RightClickMenu: NSViewRepresentable {
    let build: @MainActor () -> NSMenu

    func makeNSView(context: Context) -> MenuHostView {
        let view = MenuHostView()
        view.build = build
        return view
    }

    func updateNSView(_ view: MenuHostView, context: Context) {
        view.build = build
    }

    final class MenuHostView: NSView {
        var build: (@MainActor () -> NSMenu)?

        /// Only context clicks land here; ordinary clicks fall through to the SwiftUI row.
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent else { return nil }
            let isContextClick = event.type == .rightMouseDown || event.type == .rightMouseUp
                || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
            return isContextClick ? super.hitTest(point) : nil
        }

        override func rightMouseDown(with event: NSEvent) {
            present(at: event)
        }

        override func mouseDown(with event: NSEvent) {
            if event.modifierFlags.contains(.control) {
                present(at: event)
            } else {
                super.mouseDown(with: event)
            }
        }

        /// No synchronous menu: `present(at:)` shows it once the click is fully handled.
        override func menu(for event: NSEvent) -> NSMenu? { nil }

        private func present(at event: NSEvent) {
            guard let build, let window, let anchor = window.contentView else { return }
            let point = anchor.convert(event.locationInWindow, from: nil)
            let menu = build()
            DispatchQueue.main.async { [weak anchor] in
                guard let anchor, anchor.window?.isVisible == true else { return }
                menu.popUp(positioning: nil, at: point, in: anchor)
            }
        }
    }
}

extension View {
    func rightClickMenu(_ build: @escaping @MainActor () -> NSMenu) -> some View {
        overlay(RightClickMenu(build: build))
    }
}

/// An `NSMenuItem` that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(_ title: String, symbol: String? = nil, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
        if let symbol { image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func run() {
        MainActor.assumeIsolated { handler() }
    }
}
