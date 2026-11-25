import Foundation

/// Billing amounts travel as integer minor units (თეთრი). Never treat them as floats.
public enum Money {
    public static func string(_ minorUnits: Int?, currency: String = "GEL") -> String {
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

    public static func decimal(_ minorUnits: Int) -> Decimal { Decimal(minorUnits) / 100 }

    /// For chart axes where the currency suffix would be noise.
    public static func plain(_ minorUnits: Int) -> Double { Double(minorUnits) / 100 }
}

public enum Bytes {
    public static func string(_ value: Int?) -> String {
        guard let value else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .binary)
    }
}

public enum Durations {
    /// Seconds -> "12d 4h", "4h 9m", "9m 12s".
    public static func uptime(_ seconds: Int?) -> String {
        guard let seconds, seconds > 0 else { return "—" }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m \(seconds % 60)s"
    }

    public static func milliseconds(_ value: Int?) -> String {
        guard let value else { return "—" }
        if value < 1_000 { return "\(value) ms" }
        return String(format: "%.1f s", Double(value) / 1_000)
    }

    /// Deploy and step lengths: "3 s", "2 m 31 s", "1 m 08 s", "1 h 04 m".
    public static func elapsed(_ seconds: Int?) -> String {
        guard let seconds, seconds >= 0 else { return "—" }
        if seconds < 60 { return "\(seconds) s" }
        if seconds < 3_600 {
            return String(format: "%d m %02d s", seconds / 60, seconds % 60)
        }
        return String(format: "%d h %02d m", seconds / 3_600, (seconds % 3_600) / 60)
    }

    /// A running clock for a live deploy: "0:42", "2:05", "1:02:05".
    public static func clock(_ seconds: Int) -> String {
        let value = max(0, seconds)
        if value < 3_600 { return String(format: "%d:%02d", value / 60, value % 60) }
        return String(format: "%d:%02d:%02d", value / 3_600, (value % 3_600) / 60, value % 60)
    }
}

/// Short relative times of the Mac design: "5 s ago", "12 min ago", "2 h ago", "yesterday".
public enum RelativeTime {
    public static func ago(_ date: Date, now: Date = .now) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 5 { return "just now" }
        if seconds < 60 { return "\(seconds) s ago" }
        if seconds < 3_600 { return "\(seconds / 60) min ago" }
        if seconds < 86_400 { return "\(seconds / 3_600) h ago" }
        var calendar = Calendar.current
        calendar.timeZone = .current
        if calendar.isDate(date, inSameDayAs: now.addingTimeInterval(-86_400)) { return "yesterday" }
        let days = max(2, seconds / 86_400)
        return "\(days) days ago"
    }
}

extension Date {
    public var relativeShort: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: .now)
    }

    public var shortDateTime: String {
        formatted(date: .abbreviated, time: .shortened)
    }

    public var shortDate: String {
        formatted(date: .abbreviated, time: .omitted)
    }
}

extension Optional where Wrapped == Date {
    public var relativeShortOrDash: String { self?.relativeShort ?? "—" }
    public var shortDateTimeOrDash: String { self?.shortDateTime ?? "—" }
}

extension Int {
    /// "73 days" style, with sensible colouring handled by the caller.
    public var daysLabel: String { self == 1 ? "1 day" : "\(self) days" }
}
