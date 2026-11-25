import SwiftUI

/// "CPU 34%" over a 4 pt bar, 62 pt wide.
struct MiniMeter: View {
    var label: String
    var percent: Double?
    var width: CGFloat = 62

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(label)
                Spacer(minLength: 2)
                Text(percentText).monospacedDigit()
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)

            ProgressBar(fraction: (percent ?? 0) / 100)
        }
        .frame(width: width)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(percent == nil ? "No data" : percentText)
    }

    private var percentText: String {
        percent.map { "\(Int($0.rounded()))%" } ?? "—"
    }
}

/// A 4 pt rounded bar on the track colour.
struct ProgressBar: View {
    var fraction: Double
    var tint: Color = .accentText
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.barTrack)
                Capsule()
                    .fill(tint)
                    .frame(width: proxy.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}
