import Foundation

/// Every amount in this file is **integer minor units** (თეთრი). Divide by 100 only when
/// rendering — see `Money`.

/// `GET /api/billing/invoices`
struct Invoice: Decodable, Sendable, Hashable, Identifiable {
    var id: Int
    var number: String?
    var clientId: Int?
    var subscriptionId: Int?
    var siteId: Int?
    var periodStart: Date?
    var periodEnd: Date?
    var issuedAt: Date?
    var dueDate: Date?
    var amount: Int
    var amountPaid: Int
    var currency: String?
    var status: String
    var paidAt: Date?
    /// JSON array encoded inside a string.
    var lineItems: String?
    var notes: String?
    var client: BillingClient?
    var site: Site?
    var balance: Int?
    var amountFormatted: String?

    var currencyCode: String { currency ?? client?.currency ?? "GEL" }

    var tone: StatusTone {
        switch status.lowercased() {
        case "paid":            return .good
        case "void", "voided":  return .neutral
        case "overdue":         return .critical
        default:
            guard let dueDate else { return .warning }
            return dueDate < .now ? .critical : .warning
        }
    }

    var isOpen: Bool {
        let key = status.lowercased()
        return key != "paid" && key != "void" && key != "voided"
    }

    var isOverdue: Bool {
        guard isOpen, let dueDate else { return false }
        return dueDate < .now
    }

    var outstanding: Int { balance ?? max(0, amount - amountPaid) }

    var items: [InvoiceLineItem] { EmbeddedJSON.decode([InvoiceLineItem].self, from: lineItems) ?? [] }
}

struct InvoiceLineItem: Decodable, Sendable, Hashable {
    var description: String?
    var periodStart: Date?
    var periodEnd: Date?
    var amount: Int?
    var currency: String?
}

/// `GET /api/billing/clients`
struct BillingClient: Decodable, Sendable, Hashable, Identifiable {
    var id: Int
    var name: String
    var email: String?
    var phone: String?
    var telegramChatId: String?
    var company: String?
    var taxId: String?
    var currency: String?
    var locale: String?
    var notes: String?
    var archived: Bool
    var createdAt: Date?
    var updatedAt: Date?
    var subscriptions: [Subscription]?
    var outstanding: Int?
    var sites: [String]?

    var currencyCode: String { currency ?? "GEL" }
}

/// `GET /api/billing/subscriptions`
struct Subscription: Decodable, Sendable, Hashable, Identifiable {
    var id: Int
    var siteId: Int?
    var clientId: Int?
    var planId: Int?
    var amount: Int
    var currency: String?
    var interval: String?
    var intervalDays: Int?
    var anchorDay: Int?
    var startDate: Date?
    var nextInvoiceAt: Date?
    var status: String
    var enforcementLevel: String?
    var lastEnforcedAt: Date?
    var neverAutoSuspend: Bool
    var gracePeriodDays: Int?
    var dunningPolicy: String?
    var suspendedAt: Date?
    var cancelledAt: Date?
    var site: Site?
    var client: BillingClient?

    var currencyCode: String { currency ?? "GEL" }
    var tone: StatusTone { StatusTone(status: status) }

    var intervalLabel: String {
        if let days = intervalDays { return "every \(days) days" }
        switch (interval ?? "").lowercased() {
        case "month", "monthly": return "monthly"
        case "year", "yearly":   return "yearly"
        case "week", "weekly":   return "weekly"
        default:                 return interval ?? "—"
        }
    }
}

/// `GET /api/billing/enforcement` and `PUT` with the same shape.
struct EnforcementMode: Codable, Sendable, Hashable {
    var mode: String

    enum Known: String, CaseIterable, Identifiable, Sendable {
        case off
        case dryRun = "dry_run"
        case on

        var id: String { rawValue }

        var title: String {
            switch self {
            case .off:    return "Off"
            case .dryRun: return "Dry run"
            case .on:     return "On"
            }
        }

        var explanation: String {
            switch self {
            case .off:    return "Billing never touches a site."
            case .dryRun: return "Actions are recorded but sites are not suspended."
            case .on:     return "Overdue sites are suspended according to the dunning policy."
            }
        }

        var tone: StatusTone {
            switch self {
            case .off:    return .neutral
            case .dryRun: return .warning
            case .on:     return .good
            }
        }
    }

    var known: Known? { Known(rawValue: mode.lowercased()) }
}

/// `GET /api/billing/profitability`
struct ProfitabilityRow: Decodable, Sendable, Hashable, Identifiable {
    var siteId: Int?
    var domain: String?
    var price: Int?
    var cost: Int?
    var margin: Int?
    var currency: String?

    var id: Int { siteId ?? domain.hashValue }

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(JSONValue.self)
        siteId = value["siteId"]?.intValue
        domain = value["domain"]?.stringValue ?? value["site"]?["domain"]?.stringValue
        price = (value["price"] ?? value["revenue"] ?? value["amount"])?.intValue
        cost = value["cost"]?.intValue
        margin = (value["margin"] ?? value["profit"])?.intValue
        currency = value["currency"]?.stringValue
    }

    var currencyCode: String { currency ?? "GEL" }

    var tone: StatusTone {
        guard let margin else { return .neutral }
        if margin > 0 { return .good }
        if margin == 0 { return .warning }
        return .critical
    }
}
