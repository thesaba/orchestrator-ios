#if os(macOS)
import AppKit
import SwiftTerm
import SwiftUI

/// A SwiftTerm terminal bound to a `TerminalConnection`: output is fed in, keys and size
/// changes go out. Colours stay dark like a terminal whatever the app's appearance.
public struct TerminalSessionView: NSViewRepresentable {
    let connection: TerminalConnection
    var fontSize: CGFloat

    public init(connection: TerminalConnection, fontSize: CGFloat = 12) {
        self.connection = connection
        self.fontSize = fontSize
    }

    public func makeCoordinator() -> Coordinator { Coordinator(connection: connection) }

    public func makeNSView(context: Context) -> TerminalView {
        let view = TerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 480))
        view.terminalDelegate = context.coordinator
        view.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        view.nativeBackgroundColor = NSColor(srgbRed: 0.08, green: 0.08, blue: 0.09, alpha: 1)
        view.nativeForegroundColor = NSColor(srgbRed: 0.86, green: 0.86, blue: 0.88, alpha: 1)
        view.caretColor = NSColor(srgbRed: 0.43, green: 0.49, blue: 0.84, alpha: 1)
        connection.onOutput = { [weak view] text in view?.feed(text: text) }
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }

    public func updateNSView(_ view: TerminalView, context: Context) {
        context.coordinator.connection = connection
    }

    public final class Coordinator: NSObject, TerminalViewDelegate {
        var connection: TerminalConnection

        init(connection: TerminalConnection) {
            self.connection = connection
        }

        public func send(source: TerminalView, data: ArraySlice<UInt8>) {
            let text = String(decoding: data, as: UTF8.self)
            MainActor.assumeIsolated { connection.send(input: text) }
        }

        public func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            MainActor.assumeIsolated { connection.resize(cols: newCols, rows: newRows) }
        }

        public func setTerminalTitle(source: TerminalView, title: String) {}
        public func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        public func scrolled(source: TerminalView, position: Double) {}
        public func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}

        public func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
            if let url = URL(string: link), ["http", "https"].contains(url.scheme ?? "") {
                NSWorkspace.shared.open(url)
            }
        }

        public func clipboardCopy(source: TerminalView, content: Data) {
            if let text = String(data: content, encoding: .utf8) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
        }
    }
}
#endif
