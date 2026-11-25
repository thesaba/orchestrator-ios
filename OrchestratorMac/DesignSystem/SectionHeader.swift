import SwiftUI

/// "SERVERS" small caps header with an optional "All 10" link on the right.
struct SectionHeader: View {
    var title: String
    var trailing: String?
    var trailingAction: (() -> Void)?

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.44)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let trailing, let trailingAction {
                Button(trailing, action: trailingAction)
                    .buttonStyle(.link)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.accentText)
            }
        }
    }
}
