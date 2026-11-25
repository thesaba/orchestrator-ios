import AppKit
import SwiftUI

/// A right-click (or Control-click) menu built with AppKit at the moment of the click.
///
/// SwiftUI's `.contextMenu` rebuilds — and closes — an open menu whenever state it reads
/// changes, which a background refresh does every few seconds. An `NSMenu` built on demand
/// is a snapshot, so a refresh can no longer close it under the pointer.
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

        override func menu(for event: NSEvent) -> NSMenu? {
            build?()
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
