import Foundation

/// Invoiced and collected amounts per calendar month, for the Billing chart. Pure, so it is
/// unit-tested. Amounts stay in minor units; only invoices in `currency` count.
public struct BillingMonth: Sendable, Hashable, Identifiable {
    /// The first day of the month.
    public var month: Date
    public var invoiced: Int
    public var collected: Int

    public var id: Date { month }

    public static func last(_ count: Int, of invoices: [Invoice], currency: String,
                            now: Date = .now, calendar: Calendar = .current) -> [BillingMonth] {
        guard count > 0, let thisMonth = calendar.dateInterval(of: .month, for: now)?.start else { return [] }
        let months = (0..<count).reversed().compactMap { calendar.date(byAdding: .month, value: -$0, to: thisMonth) }
        var invoiced: [Date: Int] = [:]
        var collected: [Date: Int] = [:]
        for invoice in invoices where invoice.currencyCode == currency && invoice.status.lowercased() != "void" {
            if let issued = invoice.issuedAt ?? invoice.periodStart,
               let month = calendar.dateInterval(of: .month, for: issued)?.start {
                invoiced[month, default: 0] += invoice.amount
            }
            if invoice.amountPaid > 0, let paid = invoice.paidAt,
               let month = calendar.dateInterval(of: .month, for: paid)?.start {
                collected[month, default: 0] += invoice.amountPaid
            }
        }
        return months.map { BillingMonth(month: $0, invoiced: invoiced[$0] ?? 0, collected: collected[$0] ?? 0) }
    }
}

/// The task board's columns, in the panel's order.
public enum TaskColumn: String, CaseIterable, Sendable, Identifiable {
    case todo, inProgress = "in_progress", review, done

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .todo:       return "To do"
        case .inProgress: return "In progress"
        case .review:     return "Review"
        case .done:       return "Done"
        }
    }

    /// Tasks per column: overdue first, then by due date, then newest.
    public static func board(_ tasks: [WorkTask], now: Date = .now) -> [TaskColumn: [WorkTask]] {
        var columns: [TaskColumn: [WorkTask]] = [:]
        for task in tasks {
            let column = TaskColumn(rawValue: task.status.lowercased()) ?? (task.isDone ? .done : .todo)
            columns[column, default: []].append(task)
        }
        for key in columns.keys {
            columns[key]?.sort { lhs, rhs in
                let l = lhs.dueDate ?? .distantFuture, r = rhs.dueDate ?? .distantFuture
                if l != r { return l < r }
                return (lhs.createdAt ?? .distantPast) > (rhs.createdAt ?? .distantPast)
            }
        }
        return columns
    }
}
