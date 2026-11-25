import Foundation

/// A lenient stand-in for any JSON value.
///
/// The Orchestrator API has a wide surface and a few endpoints return loosely shaped
/// payloads (settings blobs, AI responses, file properties). Rather than fail the whole
/// screen on one unexpected field, those are decoded as `JSONValue` and read defensively.
public indirect enum JSONValue: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:              try container.encodeNil()
        case .bool(let value):   try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value):  try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    // MARK: - Readers

    public subscript(key: String) -> JSONValue? {
        if case .object(let dictionary) = self { return dictionary[key] }
        return nil
    }

    public subscript(index: Int) -> JSONValue? {
        guard case .array(let values) = self, values.indices.contains(index) else { return nil }
        return values[index]
    }

    public var stringValue: String? {
        switch self {
        case .string(let value): return value
        case .number(let value):
            guard value.isFinite else { return nil }
            return value == value.rounded() && abs(value) < 1e15 ? String(Int(value)) : String(value)
        case .bool(let value):   return String(value)
        default: return nil
        }
    }

    public var doubleValue: Double? {
        switch self {
        case .number(let value): return value
        case .string(let value): return Double(value)
        case .bool(let value):   return value ? 1 : 0
        default: return nil
        }
    }

    public var intValue: Int? {
        guard let value = doubleValue, value.isFinite else { return nil }
        return Int(value)
    }

    public var boolValue: Bool? {
        switch self {
        case .bool(let value):   return value
        case .number(let value): return value != 0
        case .string(let value): return ["true", "1", "yes", "on"].contains(value.lowercased())
        default: return nil
        }
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let values) = self { return values }
        return nil
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let dictionary) = self { return dictionary }
        return nil
    }

    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    /// Pretty-printed form, handy for "raw response" debug sheets.
    public var prettyPrinted: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self),
              let text = String(data: data, encoding: .utf8) else { return "—" }
        return text
    }
}
