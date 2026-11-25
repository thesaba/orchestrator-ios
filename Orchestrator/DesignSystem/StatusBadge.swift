import SwiftUI
import OrchestratorKit

struct StatusBadge: View {
    var text: String
    var tone: StatusTone
    var showsSymbol: Bool = true

    init(_ text: String, tone: StatusTone, showsSymbol: Bool = true) {
        self.text = text
        self.tone = tone
        self.showsSymbol = showsSymbol
    }

    init(status: String?, tone: StatusTone? = nil) {
        let raw = status?.trimmingCharacters(in: .whitespaces) ?? ""
        self.text = raw.isEmpty ? "unknown" : raw.replacingOccurrences(of: "_", with: " ")
        self.tone = tone ?? StatusTone(status: raw)
        self.showsSymbol = true
    }

    var body: some View {
        HStack(spacing: 4) {
            if showsSymbol {
                Image(systemName: tone.symbol)
                    .imageScale(.small)
            }
            Text(text.capitalized)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(tone.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tone.color.opacity(0.14), in: Capsule())
        .accessibilityLabel("Status: \(text)")
    }
}

/// Small coloured dot for dense lists where a full badge is too heavy.
struct StatusDot: View {
    var tone: StatusTone
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(tone.color)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        StatusBadge(status: "active")
        StatusBadge(status: "suspended")
        StatusBadge(status: "degraded")
        StatusBadge(status: "running")
        StatusBadge(status: "unknown_thing")
    }
    .padding()
}
