import SwiftUI

/// The rounded card behind tiles and row groups (radius 10 in the design).
struct CardBackground: ViewModifier {
    var tint: Color?

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.fill.quaternary))
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

extension View {
    func card(tint: Color? = nil) -> some View {
        modifier(CardBackground(tint: tint))
    }
}
