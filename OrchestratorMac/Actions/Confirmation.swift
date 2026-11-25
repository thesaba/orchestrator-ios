import AppKit

/// What a production-changing action asks before it runs. The message names the concrete
/// consequence, never "Are you sure?".
struct Confirmation {
    var title: String
    var consequence: String
    var confirmTitle: String
    var isDestructive = false
    /// Touch ID or the account password after the dialog.
    var requiresAuthentication = false
}

/// Shows confirmations and errors as app-modal alerts. The app is an agent, so it activates
/// first; otherwise the alert would open behind the frontmost app.
@MainActor
enum AlertPresenter {
    static func confirm(_ confirmation: Confirmation) -> Bool {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = confirmation.title
        var text = confirmation.consequence
        if confirmation.requiresAuthentication {
            text += "\n\nYou will be asked for Touch ID or your password next."
        }
        alert.informativeText = text
        alert.alertStyle = confirmation.isDestructive ? .critical : .warning
        let confirm = alert.addButton(withTitle: confirmation.confirmTitle)
        confirm.hasDestructiveAction = confirmation.isDestructive
        let cancel = alert.addButton(withTitle: "Cancel")
        cancel.keyEquivalent = "\u{1b}"
        if confirmation.isDestructive {
            // Destructive actions never run on a reflexive Return.
            confirm.keyEquivalent = ""
            cancel.keyEquivalent = "\r"
        }
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// A text field with suggestions; nil when cancelled or left empty.
    static func askRef(title: String, message: String, options: [String], initial: String?) -> String? {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        let field = NSComboBox(frame: NSRect(x: 0, y: 0, width: 280, height: 26))
        field.addItems(withObjectValues: options)
        field.completes = true
        field.stringValue = initial ?? options.first ?? ""
        field.setAccessibilityLabel("Branch, tag or commit")
        alert.accessoryView = field
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    static func showError(_ title: String, _ message: String?) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message ?? "The request failed."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    static func showInfo(_ title: String, _ message: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
