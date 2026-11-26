import AppKit
import OrchestratorKit

/// Asks for what the terminal, scripts and commands need beyond the API token: a password
/// sign-in (with the 2FA code when the account has one) and, for server shells and runs, a
/// fresh 2FA code (the panel's 15-minute step-up). Nothing typed here is stored.
@MainActor
enum AdminPrompt {
    /// - Returns: true once `admin` holds a valid password session.
    static func ensureSignedIn(_ admin: AdminAccess, suggestedEmail: String?) async -> Bool {
        if admin.isSignedIn { return true }
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Sign in with your password"
        alert.informativeText = "The terminal, scripts and commands need a password session; the API token can’t open them. "
            + "The session stays in memory only and ends when the app quits."
        let email = NSTextField(frame: NSRect(x: 0, y: 30, width: 280, height: 24))
        email.placeholderString = "Email"
        email.stringValue = admin.email ?? suggestedEmail ?? ""
        let password = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        password.placeholderString = "Password"
        let stack = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 54))
        stack.addSubview(email)
        stack.addSubview(password)
        alert.accessoryView = stack
        alert.addButton(withTitle: "Sign In")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = email.stringValue.isEmpty ? email : password
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        let address = email.stringValue, secret = password.stringValue
        do {
            if try await admin.signIn(email: address, password: secret, totpCode: nil) == .signedIn { return true }
            guard let code = askCode(title: "Two-factor code",
                                     message: "Enter the 6-digit code from your authenticator app for \(address).") else { return false }
            return try await admin.signIn(email: address, password: secret, totpCode: code) == .signedIn
        } catch {
            AlertPresenter.showError("Could not sign in", APIError.wrap(error).errorDescription)
            return false
        }
    }

    /// Signs in if needed, then steps the session up with a 2FA code unless it already is.
    static func ensureElevated(_ admin: AdminAccess, suggestedEmail: String?) async -> Bool {
        guard await ensureSignedIn(admin, suggestedEmail: suggestedEmail) else { return false }
        await admin.refreshElevation()
        if admin.isElevated() { return true }
        if admin.totpEnabled == false {
            AlertPresenter.showInfo("Turn on two-factor authentication first",
                                    "Server terminals, scripts and commands need a 2FA code, and this account has no 2FA yet. "
                                    + "Turn it on in the web panel under Settings → Security, then try again.")
            return false
        }
        guard let code = askCode(title: "Confirm with your 2FA code",
                                 message: "Server terminals, scripts and commands need a fresh code. It unlocks them for 15 minutes in this app only.") else { return false }
        do {
            try await admin.elevate(code: code)
            return admin.isElevated()
        } catch {
            AlertPresenter.showError("The code was not accepted", APIError.wrap(error).errorDescription)
            return false
        }
    }

    private static func askCode(title: String, message: String) -> String? {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 160, height: 24))
        field.placeholderString = "123456"
        field.font = .monospacedDigitSystemFont(ofSize: 16, weight: .medium)
        alert.accessoryView = field
        alert.addButton(withTitle: "Confirm")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let code = field.stringValue.filter(\.isNumber)
        return code.isEmpty ? nil : code
    }
}
