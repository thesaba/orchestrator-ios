import SwiftUI

/// The Orchestrator mark, redrawn natively from `apps/web/public/logo.svg`.
///
/// Kept as geometry rather than a bitmap so it stays crisp at any size, follows Dynamic
/// Type when embedded next to text, and can be tinted for monochrome contexts — which is
/// exactly what `logo-mono.svg` exists for on the web.
struct OrchestratorLogo: View {
    enum Style {
        /// Indigo network with the teal head node, as on the web.
        case brand
        /// Single colour, taking the surrounding foreground style.
        case monochrome(Color)
    }

    var style: Style = .brand
    var size: CGFloat = 44

    // Source coordinates, in the SVG's 0…100 viewBox.
    private static let hexagon: [CGPoint] = [
        CGPoint(x: 50, y: 20), CGPoint(x: 76, y: 35), CGPoint(x: 76, y: 65),
        CGPoint(x: 50, y: 80), CGPoint(x: 24, y: 65), CGPoint(x: 24, y: 35)
    ]
    private static let centre = CGPoint(x: 50, y: 50)
    private static let spokeTargets: [CGPoint] = [
        CGPoint(x: 50, y: 20), CGPoint(x: 76, y: 65), CGPoint(x: 24, y: 65)
    ]
    private static let nodes: [(CGPoint, CGFloat)] = [
        (CGPoint(x: 76, y: 35), 6), (CGPoint(x: 76, y: 65), 6), (CGPoint(x: 50, y: 80), 6),
        (CGPoint(x: 24, y: 65), 6), (CGPoint(x: 24, y: 35), 6), (CGPoint(x: 50, y: 50), 5.5)
    ]
    private static let headNode = (CGPoint(x: 50, y: 20), CGFloat(7))

    static let indigo = Color(red: 92 / 255, green: 106 / 255, blue: 196 / 255)
    static let teal = Color(red: 71 / 255, green: 193 / 255, blue: 191 / 255)

    private var networkColor: Color {
        switch style {
        case .brand:                 return Self.indigo
        case .monochrome(let color): return color
        }
    }

    private var headColor: Color {
        switch style {
        case .brand:                 return Self.teal
        case .monochrome(let color): return color
        }
    }

    var body: some View {
        Canvas { context, canvasSize in
            let scale = min(canvasSize.width, canvasSize.height) / 100

            func scaled(_ point: CGPoint) -> CGPoint {
                CGPoint(x: point.x * scale, y: point.y * scale)
            }

            // Faint inner spokes.
            var spokes = Path()
            for target in Self.spokeTargets {
                spokes.move(to: scaled(Self.centre))
                spokes.addLine(to: scaled(target))
            }
            context.stroke(
                spokes,
                with: .color(networkColor.opacity(0.26)),
                style: StrokeStyle(lineWidth: 2 * scale, lineCap: .round, lineJoin: .round)
            )

            // Hexagon.
            var outline = Path()
            outline.addLines(Self.hexagon.map(scaled))
            outline.closeSubpath()
            context.stroke(
                outline,
                with: .color(networkColor),
                style: StrokeStyle(lineWidth: 3 * scale, lineCap: .round, lineJoin: .round)
            )

            // Nodes.
            for (point, radius) in Self.nodes {
                let centre = scaled(point)
                let r = radius * scale
                context.fill(
                    Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2)),
                    with: .color(networkColor)
                )
            }

            let head = scaled(Self.headNode.0)
            let headRadius = Self.headNode.1 * scale
            context.fill(
                Path(ellipseIn: CGRect(x: head.x - headRadius, y: head.y - headRadius,
                                       width: headRadius * 2, height: headRadius * 2)),
                with: .color(headColor)
            )
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Orchestrator")
    }
}

/// Wordmark for headers: the mark plus the product name.
struct OrchestratorWordmark: View {
    var size: CGFloat = 28

    var body: some View {
        HStack(spacing: 8) {
            OrchestratorLogo(size: size)
            Text("Orchestrator")
                .font(.system(size: size * 0.62, weight: .semibold, design: .rounded))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Orchestrator")
    }
}

#Preview {
    VStack(spacing: 28) {
        OrchestratorLogo(size: 96)
        OrchestratorWordmark(size: 32)
        OrchestratorLogo(style: .monochrome(.secondary), size: 44)
        HStack {
            OrchestratorLogo(size: 20)
            OrchestratorLogo(size: 28)
            OrchestratorLogo(size: 36)
        }
    }
    .padding()
}
