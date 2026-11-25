import OrchestratorKit
import SwiftUI

/// Monospaced log: dim clock, bold step headers, error lines tinted across the full width.
struct LogLinesView: View {
    var lines: [LogLine]
    var fontSize: CGFloat = 12
    var follow = true
    /// Line to bring into view (clicking a step in the sidebar).
    var scrollTarget: Int?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView([.vertical]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(lines) { line in
                        LogLineRow(line: line, fontSize: fontSize)
                            .id(line.id)
                    }
                    Color.clear.frame(height: 1).id(Self.bottom)
                }
                .padding(.vertical, 8)
                .textSelection(.enabled)
            }
            .background(Color.logGround)
            .onChange(of: lines.count) {
                guard follow else { return }
                proxy.scrollTo(Self.bottom, anchor: .bottom)
            }
            .onChange(of: scrollTarget) { _, target in
                if let target { withAnimation { proxy.scrollTo(target, anchor: .top) } }
            }
            .onAppear {
                if follow { proxy.scrollTo(Self.bottom, anchor: .bottom) }
            }
        }
        .accessibilityLabel("Log output")
    }

    private static let bottom = "log-bottom"
}

private struct LogLineRow: View {
    var line: LogLine
    var fontSize: CGFloat

    var body: some View {
        let parts = LogLineStyle.split(line.text)
        let style = LogLineStyle.classify(parts.text)
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let time = parts.time {
                Text(time)
                    .foregroundStyle(style == .error ? Color.statusDangerText : Color.logDim)
            }
            Text(display(parts.text, style: style))
                .foregroundStyle(color(style))
                .fontWeight(style == .step ? .bold : .regular)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: fontSize, design: .monospaced))
        .padding(.horizontal, 14)
        .padding(.vertical, 1.5)
        .background(style == .error ? Color.tintDanger : Color.clear)
    }

    private func display(_ text: String, style: LogLineStyle) -> String {
        if text.isEmpty { return " " }
        if style == .step, let header = DeployLogParser.stepHeaderTitle(text) { return "▸ " + header }
        return text
    }

    private func color(_ style: LogLineStyle) -> Color {
        switch style {
        case .error:   return .statusDangerText
        case .success: return .statusSuccessText
        case .warning: return .statusWarningText
        case .muted:   return .logDim
        default:       return .logText
        }
    }
}
