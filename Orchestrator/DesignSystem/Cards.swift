import SwiftUI

/// A titled block used on the overview and detail screens.
struct SectionCard<Content: View>: View {
    var title: String
    var systemImage: String?
    var accessory: AnyView?
    @ViewBuilder var content: Content

    init(_ title: String,
         systemImage: String? = nil,
         accessory: AnyView? = nil,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.accessory = accessory
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label {
                    Text(title)
                } icon: {
                    if let systemImage { Image(systemName: systemImage) }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

                Spacer()
                accessory
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

/// One number with a caption. Used in grids on the overview.
struct MetricTile: View {
    var title: String
    var value: String
    var caption: String?
    var tone: StatusTone = .neutral
    var systemImage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption)
                        .foregroundStyle(tone == .neutral ? Color.secondary : tone.color)
                }
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tone == .neutral ? Color.primary : tone.color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Horizontal percentage bar for CPU / RAM / disk.
struct UsageBar: View {
    var label: String
    var percent: Int?
    var detail: String?

    private var value: Int { max(0, min(100, percent ?? 0)) }

    private var tone: StatusTone {
        switch value {
        case ..<70:  return .good
        case 70..<90: return .warning
        default:      return .critical
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.subheadline)
                Spacer()
                Text(percent == nil ? "—" : "\(value)%")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(tone.color)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.tertiarySystemFill))
                    Capsule()
                        .fill(tone.color)
                        .frame(width: geometry.size.width * CGFloat(value) / 100)
                }
            }
            .frame(height: 6)
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value) percent")
    }
}

/// Compact key/value row that copes with long values.
struct DetailRow: View {
    var label: String
    var value: String?
    var monospaced: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value?.isEmpty == false ? value! : "—")
                .font(monospaced ? .callout.monospaced() : .callout)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.callout)
    }
}
