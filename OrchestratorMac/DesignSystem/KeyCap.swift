import SwiftUI

/// A small key or badge chip: "esc", "⌥ Space", "Touch ID".
struct KeyCap: View {
    var text: String
    var onAccent = false

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(onAccent ? Color.white : Color.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(onAccent ? AnyShapeStyle(Color.white.opacity(0.2)) : AnyShapeStyle(.fill.secondary))
            }
    }
}
