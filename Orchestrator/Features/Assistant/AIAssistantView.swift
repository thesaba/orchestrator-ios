import SwiftUI

@MainActor
@Observable
final class AIAssistantViewModel {
    private(set) var config: AIConfig?
    private(set) var messages: [AIChatMessage] = []
    private(set) var isThinking = false
    var errorMessage: String?

    var draft = ""
    var siteContext: Site?

    private let api: OrchestratorAPI

    init(api: OrchestratorAPI = .shared) {
        self.api = api
    }

    var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespaces).isEmpty && !isThinking && config?.enabled == true
    }

    func loadConfig() async {
        config = try? await api.aiConfig()
    }

    func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        draft = ""
        errorMessage = nil
        let history = messages
        messages.append(AIChatMessage(role: .user, text: text))
        isThinking = true
        defer { isThinking = false }

        do {
            let response = try await api.aiChat(message: text, siteID: siteContext?.id, history: history)
            messages.append(AIChatMessage(role: .assistant, text: response.reply))
        } catch {
            errorMessage = APIError.wrap(error).errorDescription
        }
        await loadConfig()
    }

    func clear() {
        messages.removeAll()
        errorMessage = nil
    }
}

struct AIAssistantView: View {
    @State private var model = AIAssistantViewModel()
    @State private var sites: [Site] = []
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if let config = model.config, !config.enabled {
                EmptyStateView(
                    icon: "sparkles",
                    title: "Assistant is off",
                    message: config.configured
                        ? "Enable the assistant in the panel's AI settings."
                        : "No provider key is configured in the panel's AI settings."
                )
            } else {
                transcript
                composer
            }
        }
        .navigationTitle("AI assistant")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await model.loadConfig()
            sites = (try? await OrchestratorAPI.shared.sites()) ?? []
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Site context", selection: Binding(
                        get: { model.siteContext?.id },
                        set: { id in model.siteContext = sites.first { $0.id == id } }
                    )) {
                        Text("No site").tag(Int?.none)
                        ForEach(sites) { site in
                            Text(site.domain).tag(Int?.some(site.id))
                        }
                    }
                    Divider()
                    Button("Clear conversation", role: .destructive) { model.clear() }
                } label: {
                    Label("Options", systemImage: "ellipsis.circle")
                }
            }
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if model.messages.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .font(.largeTitle)
                                .foregroundStyle(.tint)
                            Text("Ask about a deploy failure, an error in the logs, or a config change.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            if let config = model.config {
                                Text("\(config.provider ?? "provider") · \(config.model ?? "model") · \(config.usageLabel)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    }

                    ForEach(model.messages) { message in
                        bubble(message)
                            .id(message.id)
                    }

                    if model.isThinking {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Thinking…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .id("thinking")
                    }

                    if let error = model.errorMessage {
                        InlineErrorBanner(message: error) { model.errorMessage = nil }
                    }
                }
                .padding(16)
            }
            .onChange(of: model.messages.count) {
                withAnimation { proxy.scrollTo(model.messages.last?.id, anchor: .bottom) }
            }
        }
    }

    private func bubble(_ message: AIChatMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(message.text)
                .font(.callout)
                .textSelection(.enabled)
                .padding(10)
                .background(
                    message.role == .user ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 12)
                )
                .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }

    private var composer: some View {
        VStack(spacing: 6) {
            if let site = model.siteContext {
                HStack(spacing: 6) {
                    Image(systemName: "globe")
                        .font(.caption2)
                    Text("Context: \(site.domain)")
                        .font(.caption2)
                    Button {
                        model.siteContext = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
            }

            HStack(spacing: 10) {
                TextField("Ask something…", text: $model.draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .focused($inputFocused)

                Button {
                    inputFocused = false
                    Task { await model.send() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(!model.canSend)
            }
            .padding(.horizontal, 16)

            Text("Answers are generated — verify before acting. The server redacts secrets before sending context.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
        .padding(.vertical, 10)
        .background(.bar)
    }
}
