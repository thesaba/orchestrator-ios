import Foundation

/// The shape-coded status marks of the Mac design. Status never relies on colour alone:
/// each mark has its own symbol and a spoken label.
public enum HealthMark: Int, Sendable, Hashable, Comparable {
    /// Sorted worst first: failure, warning, deploying, unknown, healthy.
    case failure = 0
    case warning = 1
    case deploying = 2
    case unknown = 3
    case healthy = 4

    public static func < (lhs: HealthMark, rhs: HealthMark) -> Bool { lhs.rawValue < rhs.rawValue }

    /// SF Symbol for the mark.
    public var symbol: String {
        switch self {
        case .healthy:   return "circle.fill"
        case .warning:   return "exclamationmark.triangle.fill"
        case .failure:   return "xmark.circle.fill"
        case .unknown:   return "circle.dashed"
        case .deploying: return "arrow.up"
        }
    }

    /// What VoiceOver reads for the mark.
    public var accessibilityLabel: String {
        switch self {
        case .healthy:   return "Healthy"
        case .warning:   return "Warning"
        case .failure:   return "Failure"
        case .unknown:   return "Unknown"
        case .deploying: return "Deploying"
        }
    }
}
