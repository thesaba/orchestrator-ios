import Foundation

/// Billing amounts travel as integer minor units (თეთრი). Never treat them as floats.
enum Money {
    static func string(_ minorUnits: Int?, currency: String = "GEL") -> String {
        guard let minorUnits else { return "—" }
        let amount = Decimal(minorUnits) / 100
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = true
        let number = formatter.string(from: amount as NSDecimalNumber) ?? "0.00"
        return "\(number) \(currency)"
    }

    static func decimal(_ minorUnits: Int) -> Decimal { Decimal(minorUnits) / 100 }

    /// For chart axes where the currency suffix would be noise.
    static func plain(_ minorUnits: Int) -> Double { Double(minorUnits) / 100 }
}

enum Bytes {
    static func string(_ value: Int?) -> String {
        guard let value else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .binary)
    }
}

enum Durations {
    /// Seconds -> "12d 4h", "4h 9m", "9m 12s".
    static func uptime(_ seconds: Int?) -> String {
        guard let seconds, seconds > 0 else { return "—" }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m \(seconds % 60)s"
    }

    static func milliseconds(_ value: Int?) -> String {
        guard let value else { return "—" }
        if value < 1_000 { return "\(value) ms" }
        return String(format: "%.1f s", Double(value) / 1_000)
    }
}

extension Date {
    var relativeShort: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: .now)
    }

    var shortDateTime: String {
        formatted(date: .abbreviated, time: .shortened)
    }

    var shortDate: String {
        formatted(date: .abbreviated, time: .omitted)
    }
}

extension Optional where Wrapped == Date {
    var relativeShortOrDash: String { self?.relativeShort ?? "—" }
    var shortDateTimeOrDash: String { self?.shortDateTime ?? "—" }
}

extension Int {
    /// "73 days" style, with sensible colouring handled by the caller.
    var daysLabel: String { self == 1 ? "1 day" : "\(self) days" }
}
