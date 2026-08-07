import Foundation

/// The API is not consistent about date formats:
///   * Prisma rows      -> "2026-07-27T22:42:38.368Z"      (ISO-8601, fractional)
///   * some routes      -> "2026-08-06T14:30:23Z"          (ISO-8601, no fraction)
///   * SSL certificates -> "2026-10-18 18:47:33+00:00"     (space separated, offset)
///   * Laravel log lines-> "2026-07-27 22:44:12"           (space separated, server local)
///   * day buckets      -> "2026-07-14"
/// One parser handles all of them.
enum DateParsing {
    private static func iso(_ options: ISO8601DateFormatter.Options) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = options
        return formatter
    }

    private static func fixed(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter
    }

    private static let isoFractional = iso([.withInternetDateTime, .withFractionalSeconds])
    private static let isoPlain = iso([.withInternetDateTime])
    private static let spaceOffset = fixed("yyyy-MM-dd HH:mm:ssXXXXX")
    private static let spaceZoneless = fixed("yyyy-MM-dd HH:mm:ss")
    private static let dayOnly = fixed("yyyy-MM-dd")

    static func parse(_ string: String) -> Date? {
        let value = string.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return nil }
        if value.contains("T") {
            if let date = isoFractional.date(from: value) { return date }
            if let date = isoPlain.date(from: value) { return date }
        }
        if let date = spaceOffset.date(from: value) { return date }
        if let date = spaceZoneless.date(from: value) { return date }
        if let date = dayOnly.date(from: value) { return date }
        if let date = isoFractional.date(from: value) { return date }
        return isoPlain.date(from: value)
    }

    /// Epoch values arrive in seconds or milliseconds depending on the route.
    static func parse(epoch value: Double) -> Date {
        value > 100_000_000_000 ? Date(timeIntervalSince1970: value / 1000) : Date(timeIntervalSince1970: value)
    }

    static let decodingStrategy: JSONDecoder.DateDecodingStrategy = .custom { decoder in
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            throw DecodingError.valueNotFound(Date.self, .init(codingPath: container.codingPath, debugDescription: "null date"))
        }
        if let string = try? container.decode(String.self) {
            if let date = parse(string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognised date string: \(string)")
        }
        if let number = try? container.decode(Double.self) {
            return parse(epoch: number)
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognised date value")
    }

    static let encodingStrategy: JSONEncoder.DateEncodingStrategy = .custom { date, encoder in
        var container = encoder.singleValueContainer()
        try container.encode(isoFractional.string(from: date))
    }
}

/// Several columns hold JSON *inside* a string (`site.tags == "[]"`,
/// `invoice.lineItems == "[{...}]"`, `dashboardPreset.config`). This unwraps them.
enum EmbeddedJSON {
    static func decode<T: Decodable>(_ type: T.Type, from string: String?) -> T? {
        guard let string, !string.isEmpty, let data = string.data(using: .utf8) else { return nil }
        return try? APIClient.decoder.decode(type, from: data)
    }

    static func stringArray(from string: String?) -> [String] {
        decode([String].self, from: string) ?? []
    }
}
