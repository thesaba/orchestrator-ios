import SwiftUI
import OrchestratorKit

struct LogConsoleView: View {
    var lines: [LogLine]
    var isStreaming: Bool = false
    var autoScroll: Bool = true

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(lines) { line in
                        Text(line.text.isEmpty ? " " : line.text)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(line.tone?.color ?? .primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(line.id)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(bottomAnchor)
                }
                .padding(10)
            }
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .onChange(of: lines.count) {
                guard autoScroll else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(bottomAnchor, anchor: .bottom)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isStreaming {
                    HStack(spacing: 5) {
                        ProgressView().controlSize(.mini)
                        Text("streaming")
                            .font(.caption2)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.regularMaterial, in: Capsule())
                    .padding(8)
                }
            }
        }
    }

    private var bottomAnchor: String { "log-bottom-anchor" }
}
