import OrchestratorKit
import SwiftUI

// Motion and colour shared by the main window: skeletons while data loads, charts that draw
// in, cards that fade up, hover highlights and the colours of each section. Everything here
// honours Reduce Motion: shimmer and movement stop, content just appears.

// MARK: - Palette

/// The brighter accents the app uses besides the logo's indigo and teal.
enum Vivid {
    static let indigo = Color.chartCPU
    static let teal = Color.brandTeal
    static let blue = Color(red: 0.27, green: 0.56, blue: 0.98)
    static let green = Color(red: 0.20, green: 0.74, blue: 0.42)
    static let orange = Color(red: 0.99, green: 0.58, blue: 0.20)
    static let pink = Color(red: 0.95, green: 0.36, blue: 0.56)
    static let purple = Color(red: 0.64, green: 0.43, blue: 0.95)
    static let yellow = Color(red: 0.98, green: 0.76, blue: 0.18)
    static let slate = Color(red: 0.52, green: 0.58, blue: 0.68)
}

/// A symbol on a soft tinted square, for tiles and headers.
struct IconBadge: View {
    var symbol: String
    var tint: Color
    var size: CGFloat = 26

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(tint.opacity(0.16)))
            .accessibilityHidden(true)
    }
}

// MARK: - Skeletons

/// A light band that sweeps across its content, masked to the content's shape.
struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion {
                    GeometryReader { proxy in
                        let width = proxy.size.width
                        LinearGradient(colors: [.clear, .white.opacity(colorScheme == .dark ? 0.10 : 0.45), .clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: max(80, width * 0.45))
                            .offset(x: phase * (width * 1.6) - width * 0.5)
                    }
                    .mask(content)
                    .allowsHitTesting(false)
                }
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.35).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}

extension View {
    func shimmering() -> some View { modifier(Shimmer()) }
}

/// One grey placeholder bar.
struct SkeletonBar: View {
    var width: CGFloat?
    var height: CGFloat = 10

    var body: some View {
        RoundedRectangle(cornerRadius: height / 2.5, style: .continuous)
            .fill(.fill.tertiary)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
}

/// Rows of placeholder bars in a card, shown while a list loads.
struct SkeletonRows: View {
    var count = 3
    var rowHeight: CGFloat = 34

    private static let widths: [CGFloat] = [0.62, 0.45, 0.74, 0.52, 0.68, 0.4]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                if index > 0 { Divider() }
                GeometryReader { proxy in
                    HStack(spacing: 10) {
                        Circle().fill(.fill.tertiary).frame(width: 12, height: 12)
                        VStack(alignment: .leading, spacing: 5) {
                            SkeletonBar(width: proxy.size.width * Self.widths[index % Self.widths.count], height: 9)
                            SkeletonBar(width: proxy.size.width * Self.widths[(index + 3) % Self.widths.count] * 0.6, height: 7)
                        }
                        Spacer(minLength: 0)
                        SkeletonBar(width: 54, height: 9)
                    }
                    .frame(maxHeight: .infinity)
                }
                .padding(.horizontal, 12)
                .frame(height: rowHeight)
            }
        }
        .shimmering()
        .card()
        .accessibilityElement()
        .accessibilityLabel("Loading")
    }
}

/// Placeholder tiles while the summary loads.
struct SkeletonTiles: View {
    var count = 4

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: count), spacing: 12) {
            ForEach(0..<count, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 8) {
                    SkeletonBar(width: 70, height: 9)
                    SkeletonBar(width: 96, height: 20)
                    SkeletonBar(width: 120, height: 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .card()
            }
        }
        .shimmering()
        .accessibilityElement()
        .accessibilityLabel("Loading")
    }
}

/// A placeholder chart: a soft wave inside a card.
struct SkeletonChart: View {
    var height: CGFloat = 110

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { SkeletonBar(width: 40, height: 9); Spacer(); SkeletonBar(width: 34, height: 9) }
            WaveShape()
                .fill(.fill.tertiary)
                .frame(height: height * 0.6)
            SkeletonBar(width: 110, height: 8)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: height)
        .shimmering()
        .card()
        .accessibilityElement()
        .accessibilityLabel("Loading")
    }
}

private struct WaveShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.maxY))
        let steps = 24
        for step in 0...steps {
            let x = rect.width * CGFloat(step) / CGFloat(steps)
            let y = rect.midY + sin(CGFloat(step) / 3.2) * rect.height * 0.22 + cos(CGFloat(step) / 1.7) * rect.height * 0.08
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Skeleton rows while loading, otherwise the empty-state row.
struct LoadingOrEmptyRow: View {
    var isLoading: Bool
    var text: String
    var symbol: String
    var rows = 3

    var body: some View {
        if isLoading {
            SkeletonRows(count: rows)
        } else {
            EmptyRow(text: text, symbol: symbol)
        }
    }
}

// MARK: - Motion

/// Draws a chart in from left to right the first time it appears.
struct ChartReveal: ViewModifier {
    var delay: Double = 0
    @State private var progress: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .mask(alignment: .leading) {
                // Taller than the chart, so axis labels and readouts that sit on its edge
                // are not cut off; only the left-to-right wipe is masked.
                GeometryReader { proxy in
                    Rectangle()
                        .frame(width: proxy.size.width * progress + (progress >= 1 ? 40 : 0),
                               height: proxy.size.height + 60)
                        .offset(y: -30)
                }
            }
            .onAppear {
                if reduceMotion { progress = 1; return }
                withAnimation(.easeOut(duration: 0.9).delay(delay)) { progress = 1 }
            }
    }
}

/// Fades and slides a card up into place the first time it appears.
struct AppearIn: ViewModifier {
    var delay: Double = 0
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 10)
            .onAppear {
                withAnimation(.spring(duration: 0.45, bounce: 0.15).delay(reduceMotion ? 0 : delay)) { shown = true }
            }
    }
}

/// A soft background under the pointer, for clickable rows.
struct HoverHighlight: ViewModifier {
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(hovering ? AnyShapeStyle(.fill.quaternary) : AnyShapeStyle(.clear))
            .animation(.easeOut(duration: 0.15), value: hovering)
            .onHover { hovering = $0 }
    }
}

extension View {
    func chartReveal(delay: Double = 0) -> some View { modifier(ChartReveal(delay: delay)) }
    func appearIn(delay: Double = 0) -> some View { modifier(AppearIn(delay: delay)) }
    func hoverHighlight() -> some View { modifier(HoverHighlight()) }
}

// MARK: - Section colours and symbols

extension SidebarItem {
    var tint: Color {
        switch self {
        case .dashboard:  return Vivid.indigo
        case .alerts:     return Vivid.orange
        case .sites:      return Vivid.blue
        case .servers:    return Vivid.teal
        case .monitoring: return Vivid.pink
        case .billing:    return Vivid.green
        case .tasks:      return Vivid.orange
        case .assistant:  return Vivid.purple
        case .users:      return Vivid.indigo
        case .audit:      return Vivid.slate
        case .automation: return Vivid.yellow
        }
    }
}

extension SiteTab {
    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .deploys:  return "arrow.up.circle"
        case .config:   return "slider.horizontal.3"
        case .ssl:      return "lock.shield"
        case .workers:  return "gearshape.2"
        case .logs:     return "doc.text.magnifyingglass"
        case .artisan:  return "terminal"
        case .files:    return "folder"
        case .database: return "cylinder.split.1x2"
        case .security: return "hand.raised"
        }
    }

    var tint: Color {
        switch self {
        case .overview: return Vivid.indigo
        case .deploys:  return Vivid.blue
        case .config:   return Vivid.orange
        case .ssl:      return Vivid.green
        case .workers:  return Vivid.teal
        case .logs:     return Vivid.slate
        case .artisan:  return Vivid.purple
        case .files:    return Vivid.yellow
        case .database: return Vivid.pink
        case .security: return Vivid.green
        }
    }
}
