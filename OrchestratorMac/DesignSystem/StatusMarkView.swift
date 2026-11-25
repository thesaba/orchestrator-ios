import OrchestratorKit
import SwiftUI

/// Round dot, triangle, cross, dashed ring or arrow — never colour alone. VoiceOver reads
/// the mark as a word.
struct StatusMarkView: View {
    var mark: HealthMark
    var size: CGFloat = 14

    var body: some View {
        Group {
            switch mark {
            case .healthy:
                Circle()
                    .fill(Color.statusSuccess)
                    .frame(width: size * 0.57, height: size * 0.57)
            default:
                Image(systemName: mark.symbol)
                    .font(.system(size: size * (mark == .deploying ? 0.95 : 0.9), weight: .semibold))
                    .foregroundStyle(mark.tint)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(mark.accessibilityLabel)
    }
}

extension HealthMark {
    /// Fill colour of the mark.
    var tint: Color {
        switch self {
        case .healthy:   return .statusSuccess
        case .warning:   return .statusWarning
        case .failure:   return .statusDanger
        case .unknown:   return .secondary
        case .deploying: return .accentText
        }
    }

    /// Text colour for a label next to the mark.
    var textTint: Color {
        switch self {
        case .warning:   return .statusWarningText
        case .failure:   return .statusDangerText
        case .deploying: return .accentText
        default:         return .secondary
        }
    }
}
