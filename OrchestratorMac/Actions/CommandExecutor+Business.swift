import AppKit
import OrchestratorKit

/// Billing and account write paths. Recording a payment or voiding an invoice changes the
/// books (and can lift or trigger a site's suspension); revoking a token cuts off whatever
/// uses it. Each confirms with the consequence and needs Touch ID.
extension CommandExecutor {
    func recordPayment(invoice: Invoice, amountMinorUnits: Int, method: OrchestratorAPI.PaymentMethod,
                       reference: String?) async -> Bool {
        let amount = Money.string(amountMinorUnits, currency: invoice.currencyCode)
        let number = invoice.number ?? "#\(invoice.id)"
        let client = invoice.client?.name ?? "the client"
        let partial = amountMinorUnits < invoice.outstanding
        let confirmation = Confirmation(
            title: "Record \(amount) paid on \(number)?",
            consequence: "Marks \(amount) from \(client) as received by \(method.title.lowercased())"
                + (partial ? ". The invoice stays partly unpaid (\(Money.string(invoice.outstanding - amountMinorUnits, currency: invoice.currencyCode)) left)."
                           : " and closes the invoice. If this was the last unpaid invoice of a suspended site, the site is restored.")
                + " No money moves; this only updates the records.",
            confirmTitle: "Record Payment", isDestructive: false, requiresAuthentication: true)
        guard await confirm(confirmation, reason: "record a payment on \(number)") else { return false }
        do {
            let reply = try await api.payInvoice(invoice.id, amountMinorUnits: amountMinorUnits, method: method, reference: reference)
            if reply.restored == true {
                environment.notifications.postInfo(title: "Site restored", body: "\(number) is paid, so its site serves visitors again.")
            }
            return true
        } catch {
            AlertPresenter.showError("Could not record the payment", APIError.wrap(error).errorDescription)
            return false
        }
    }

    func voidInvoice(_ invoice: Invoice) async -> Bool {
        let number = invoice.number ?? "#\(invoice.id)"
        let confirmation = Confirmation(
            title: "Void \(number)?",
            consequence: "\(number) (\(Money.string(invoice.amount, currency: invoice.currencyCode)) for \(invoice.client?.name ?? "the client")) "
                + "no longer counts as owed and can’t be paid. This cannot be undone; issue a new invoice if it was a mistake.",
            confirmTitle: "Void Invoice", isDestructive: true, requiresAuthentication: true)
        guard await confirm(confirmation, reason: "void \(number)") else { return false }
        do {
            try await api.voidInvoice(invoice.id)
            return true
        } catch {
            AlertPresenter.showError("Could not void \(number)", APIError.wrap(error).errorDescription)
            return false
        }
    }

    func revokeToken(_ token: APIToken) async -> Bool {
        let confirmation = Confirmation(
            title: "Revoke the token “\(token.name)”?",
            consequence: "Anything that signs in with it (a script, CI, an MCP client, this app if it uses it) gets 401 from now on. "
                + "This cannot be undone; create a new token to replace it.",
            confirmTitle: "Revoke", isDestructive: true, requiresAuthentication: true)
        guard await confirm(confirmation, reason: "revoke the token \(token.name)") else { return false }
        do {
            try await api.revokeToken(id: token.id)
            return true
        } catch {
            AlertPresenter.showError("Could not revoke the token", APIError.wrap(error).errorDescription)
            return false
        }
    }
}
