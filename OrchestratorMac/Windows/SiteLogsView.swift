import OrchestratorKit
import SwiftUI

/// The site's Laravel log (`GET /sites/:id/logs?level=&search=&lines=`), read-only.
struct SiteLogsView: View {
    let siteID: Int
    let domain: String
    let api: OrchestratorAPI

    @State private var entries: [SiteLogsResponse.Entry] = []
    @State private var level = ""
    @State private var search = ""
    @State private var isLoading = false
    @State private var error: String?

    private static let levels = ["", "error", "warning", "info", "debug"]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Picker("Level", selection: $level) {
                    ForEach(Self.levels, id: \.self) { Text($0.isEmpty ? "All levels" : $0.capitalized).tag($0) }
                }
                .frame(width: 160)
                TextField("Search", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await load() } }
                Button {
                    Task { await load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading)
                .keyboardShortcut("r", modifiers: .command)
                .accessibilityLabel("Refresh")
            }
            .padding(12)
            Divider()

            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Color.statusDangerText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if entries.isEmpty {
                Group {
                    if isLoading { ProgressView() } else { Text("No log entries").foregroundStyle(.secondary) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(entries) { entry in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text((entry.level ?? "log").uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(color(entry.level))
                            if let time = entry.timestamp {
                                Text(time.formatted(date: .abbreviated, time: .standard))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(entry.message)
                            .font(.system(size: 12, design: .monospaced))
                            .lineLimit(6)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .frame(minWidth: 560, maxWidth: .infinity, minHeight: 380, maxHeight: .infinity)
        .task(id: level) { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            entries = try await api.siteLogs(siteID: siteID, level: level.isEmpty ? nil : level,
                                             search: search, lines: 300).entries
            error = nil
        } catch {
            self.error = APIError.wrap(error).errorDescription
        }
    }

    private func color(_ level: String?) -> Color {
        switch (level ?? "").lowercased() {
        case "error", "critical", "alert", "emergency": return .statusDangerText
        case "warning":                                  return .statusWarningText
        default:                                         return .secondary
        }
    }
}
