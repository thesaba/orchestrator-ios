import Foundation
import Testing
@testable import OrchestratorKit

@Suite("Billing chart, task board and automation")
struct WorkspaceTests {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    @Test func monthsSumInvoicedAndCollected() throws {
        let json = """
        [{"id":1,"amount":12000,"amountPaid":12000,"currency":"GEL","status":"paid","issuedAt":"2026-10-01T00:00:00.000Z","paidAt":"2026-11-03T10:00:00.000Z"},
         {"id":2,"amount":8600,"amountPaid":0,"currency":"GEL","status":"open","issuedAt":"2026-11-01T00:00:00.000Z"},
         {"id":3,"amount":5000,"amountPaid":0,"currency":"GEL","status":"void","issuedAt":"2026-11-02T00:00:00.000Z"},
         {"id":4,"amount":900,"amountPaid":900,"currency":"USD","status":"paid","issuedAt":"2026-11-02T00:00:00.000Z","paidAt":"2026-11-02T00:00:00.000Z"}]
        """
        let invoices = try Fixtures.decode([Invoice].self, json)
        let months = BillingMonth.last(3, of: invoices, currency: "GEL", now: Fixtures.now, calendar: utc)
        #expect(months.count == 3)
        #expect(months.map(\.invoiced) == [0, 12000, 8600])
        #expect(months.map(\.collected) == [0, 0, 12000])
        #expect(OrchestratorAPI.PaymentMethod.bank.rawValue == "bank_transfer")
    }

    @Test func boardGroupsByStatusAndDueDate() throws {
        let json = """
        {"tasks":[{"id":1,"title":"Later","status":"todo","dueDate":"2026-12-10T00:00:00.000Z"},
                  {"id":2,"title":"Sooner","status":"todo","dueDate":"2026-11-28T00:00:00.000Z"},
                  {"id":3,"title":"Doing","status":"in_progress"},
                  {"id":4,"title":"Shipped","status":"done"}]}
        """
        let tasks = try Fixtures.decode(TasksResponse.self, json).tasks
        let board = TaskColumn.board(tasks, now: Fixtures.now)
        #expect(board[.todo]?.map(\.title) == ["Sooner", "Later"])
        #expect(board[.inProgress]?.count == 1)
        #expect(board[.done]?.first?.title == "Shipped")
        #expect(board[.review] == nil)
    }

    @Test func automationDecodes() throws {
        let rules = try Fixtures.decode(AutomationRulesResponse.self, #"{"rules":[{"id":1,"name":"Deploy failed","trigger":"deploy.failed","conditions":[],"actionType":"telegram","actionConfig":{},"enabled":true,"dryRun":false,"lastFiredAt":null,"createdAt":"2026-11-01T00:00:00.000Z","updatedAt":"2026-11-01T00:00:00.000Z"}]}"#)
        #expect(rules.rules.first?.trigger == "deploy.failed")
        let hooks = try Fixtures.decode(WebhooksResponse.self, #"{"webhooks":[{"id":2,"name":"n8n","url":"https://n8n.example/hook","events":[],"active":true,"hasSecret":true,"createdAt":"2026-11-01T00:00:00.000Z"}]}"#)
        #expect(hooks.webhooks.first?.events.isEmpty == true)
    }
}
