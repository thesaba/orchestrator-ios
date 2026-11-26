import OrchestratorKit
import SwiftUI

/// Chat with the panel's AI assistant, optionally about one site. The assistant reads the
/// panel; it does not run actions from here. Messages go to the AI provider configured in
/// the panel.
struct AssistantView: View {
    let environment: AppEnvironment

    @State private var config: AIConfig?
    @State private var messages: [AIChatMessage] = []
    @State private var input = ""
    @State private var siteID: Int?
    @State private var isSending = false
    @State private var error: String?

    private var sites: [SiteStatus] { environment.store.overview.sites.sorted { $0.domain < $1.domain } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            transcript
            Divider()
            composer
        }
        .task { config = try? await environment.api.aiConfig() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles").foregroundStyle(Color.accentText).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("AI Assistant").font(.system(size: 13, weight: .semibold))
                Text(configText).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Picker("About", selection: $siteID) {
                Text("The whole panel").tag(Int?.none)
                ForEach(sites) { Text($0.domain).tag(Optional($0.id)) }
            }
            .fixedSize()
            .controlSize(.small)
            Button("Clear") { messages = []; error = nil }
                .controlSize(.small)
                .disabled(messages.isEmpty)
        }
        .padding(.horizontal, 20)
        .frame(height: 52)
    }

    private var configText: String {
        guard let config else { return "Checking the assistant…" }
        guard config.enabled, config.configured else { return "Not set up in the panel’s settings" }
        return [config.model, config.usageLabel].compactMap { $0 }.joined(separator: " · ")
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if messages.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Ask about your sites, servers, deploys or invoices.").foregroundStyle(.secondary)
                            ForEach(["What changed since yesterday?", "Why did the last deploy fail?", "Which invoices are overdue?"], id: \.self) { prompt in
                                Button(prompt) { send(prompt) }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .disabled(!canSend)
                            }
                        }
                        .padding(.top, 8)
                    }
                    ForEach(messages) { message in
                        Bubble(message: message).id(message.id)
                    }
                    if isSending {
                        HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Thinking…").foregroundStyle(.secondary) }
                            .id("thinking")
                    }
                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Color.statusDangerText).font(.system(size: 12))
                    }
                }
                .padding(20)
                .frame(maxWidth: 820, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: messages.count) {
                withAnimation { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
            }
        }
    }

    private var canSend: Bool {
        !isSending && config?.enabled == true && config?.configured == true && config?.isThrottled != true
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("Ask the assistant", text: $input, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .onSubmit { send(input) }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.fill.tertiary))
            Button {
                send(input)
            } label: {
                Image(systemName: "arrow.up").font(.system(size: 13, weight: .bold))
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSend || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .keyboardShortcut(.return, modifiers: .command)
            .accessibilityLabel("Send")
        }
        .padding(14)
    }

    private func send(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, canSend else { return }
        let history = messages
        messages.append(AIChatMessage(role: .user, text: question))
        input = ""
        error = nil
        isSending = true
        let site = siteID
        Task {
            defer { isSending = false }
            do {
                let reply = try await environment.api.aiChat(message: question, siteID: site, history: Array(history.suffix(12)))
                messages.append(AIChatMessage(role: .assistant, text: reply.reply))
                config = try? await environment.api.aiConfig()
            } catch {
                self.error = APIError.wrap(error).errorDescription
            }
        }
    }
}

private struct Bubble: View {
    var message: AIChatMessage

    var body: some View {
        let isUser = message.role == .user
        HStack {
            if isUser { Spacer(minLength: 80) }
            Group {
                if isUser {
                    Text(message.text)
                } else {
                    Text((try? AttributedString(markdown: message.text,
                                                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(message.text))
                }
            }
            .font(.system(size: 13))
            .textSelection(.enabled)
            .foregroundStyle(isUser ? Color.white : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isUser ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.fill.quaternary)))
            if !isUser { Spacer(minLength: 80) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isUser ? "You" : "Assistant")
        .accessibilityValue(message.text)
    }
}
