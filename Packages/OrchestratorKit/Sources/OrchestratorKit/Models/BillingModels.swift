import Foundation

/// Every amount in this file is **integer minor units** (თეთრი). Divide by 100 only when
/// rendering — see `Money`.

/// `GET /api/billing/invoices`
public struct Invoice: Decodable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var number: String?
    public var clientId: Int?
    public var subscriptionId: Int?
    public var siteId: Int?
    public var periodStart: Date?
    public var periodEnd: Date?
    public var issuedAt: Date?
    public var dueDate: Date?
    public var amount: Int
    public var amountPaid: Int
    public var currency: String?
    public var status: String
    public var paidAt: Date?
    /// JSON array encoded inside a string.
    public var lineItems: String?
    public var notes: String?
    public var client: BillingClient?
    public var site: Site?
    public var balance: Int?
    public var amountFormatted: String?

    public var currencyCode: String { currency ?? client?.currency ?? "GEL" }

    public var tone: StatusTone {
        switch status.lowercased() {
        case "paid":            return .good
        case "void", "voided":  return .neutral
        case "overdue":         return .critical
        default:
            guard let dueDate else { return .warning }
            return dueDate < .now ? .critical : .warning
        }
    }

    public var isOpen: Bool {
        let key = status.lowercased()
        return key != "paid" && key != "void" && key != "voided"
    }

    public var isOverdue: Bool {
        guard isOpen, let dueDate else { return false }
        return dueDate < .now
    }

    public var outstanding: Int { balance ?? max(0, amount - amountPaid) }

    public var items: [InvoiceLineItem] { EmbeddedJSON.decode([InvoiceLineItem].self, from: lineItems) ?? [] }
}

public struct InvoiceLineItem: Decodable, Sendable, Hashable {
    public var description: String?
    public var periodStart: Date?
    public var periodEnd: Date?
    public var amount: Int?
    public var currency: String?
}

/// `GET /api/billing/clients`
public struct BillingClient: Decodable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var name: String
    public var email: String?
    public var phone: String?
    public var telegramChatId: String?
    public var company: String?
    public var taxId: String?
    public var currency: String?
    public var locale: String?
    public var notes: String?
    public var archived: Bool
    public var createdAt: Date?
    public var updatedAt: Date?
    public var subscriptions: [Subscription]?
    public var outstanding: Int?
    public var sites: [String]?

    public var currencyCode: String { currency ?? "GEL" }
}

/// `GET /api/billing/subscriptions`
public struct Subscription: Decodable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var siteId: Int?
    public var clientId: Int?
    public var planId: Int?
    public var amount: Int
    public var currency: String?
    public var interval: String?
    public var intervalDays: Int?
    public var anchorDay: Int?
    public var startDate: Date?
    public var nextInvoiceAt: Date?
    public var status: String
    public var enforcementLevel: String?
    public var lastEnforcedAt: Date?
    public var neverAutoSuspend: Bool
    public var gracePeriodDays: Int?
    public var dunningPolicy: String?
    public var suspendedAt: Date?
    public var cancelledAt: Date?
    public var site: Site?
    public var client: BillingClient?

    public var currencyCode: String { currency ?? "GEL" }
    public var tone: StatusTone { StatusTone(status: status) }

    public var intervalLabel: String {
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
public struct EnforcementMode: Codable, Sendable, Hashable {
    public var mode: String

    public enum Known: String, CaseIterable, Identifiable, Sendable {
        case off
        case dryRun = "dry_run"
        case on

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .off:    return "Off"
            case .dryRun: return "Dry run"
            case .on:     return "On"
            }
        }

        public var explanation: String {
            switch self {
            case .off:    return "Billing never touches a site."
            case .dryRun: return "Actions are recorded but sites are not suspended."
            case .on:     return "Overdue sites are suspended according to the dunning policy."
            }
        }

        public var tone: StatusTone {
            switch self {
            case .off:    return .neutral
            case .dryRun: return .warning
            case .on:     return .good
            }
        }
    }

    public var known: Known? { Known(rawValue: mode.lowercased()) }
}

/// `GET /api/billing/profitability`
public struct ProfitabilityRow: Decodable, Sendable, Hashable, Identifiable {
    public var siteId: Int?
    public var domain: String?
    public var price: Int?
    public var cost: Int?
    public var margin: Int?
    public var currency: String?

    public var id: Int { siteId ?? domain.hashValue }

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(JSONValue.self)
        siteId = value["siteId"]?.intValue
        domain = value["domain"]?.stringValue ?? value["site"]?["domain"]?.stringValue
        price = (value["price"] ?? value["revenue"] ?? value["amount"])?.intValue
        cost = value["cost"]?.intValue
        margin = (value["margin"] ?? value["profit"])?.intValue
        currency = value["currency"]?.stringValue
    }

    public var currencyCode: String { currency ?? "GEL" }

    public var tone: StatusTone {
        guard let margin else { return .neutral }
        if margin > 0 { return .good }
        if margin == 0 { return .warning }
        return .critical
    }
}
