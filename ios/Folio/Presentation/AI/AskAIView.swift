import SwiftUI

struct AskAIView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var inputText = ""
    @State private var messages: [ChatMessage] = ChatMessage.mockConversation
    @State private var isThinking = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: Spacing.md) {
                        welcomeHeader
                        ForEach(messages) { message in
                            chatBubble(message)
                        }
                        if isThinking {
                            thinkingIndicator
                        }
                    }
                    .padding(.horizontal, Spacing.screenPadding)
                    .padding(.vertical, Spacing.md)
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            inputBar
        }
        .background(Color.folio.background)
        .navigationTitle(String(localized: "askai.title", defaultValue: "Ask AI"))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Welcome

    private var welcomeHeader: some View {
        VStack(spacing: Spacing.xs) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 36))
                .foregroundStyle(Color.folio.accent)

            Text(String(localized: "askai.welcome", defaultValue: "Ask about your collection"))
                .font(Typography.listTitle)
                .foregroundStyle(Color.folio.textPrimary)

            Text(String(localized: "askai.welcomeSub", defaultValue: "AI will search across all your saved articles to answer"))
                .font(Typography.caption)
                .foregroundStyle(Color.folio.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, Spacing.md)
    }

    // MARK: - Chat Bubble

    private func chatBubble(_ message: ChatMessage) -> some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            if message.isUser { Spacer(minLength: 60) }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: Spacing.xs) {
                Text(message.content)
                    .font(Typography.body)
                    .foregroundStyle(message.isUser ? .white : Color.folio.textPrimary)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(message.isUser ? Color.folio.accent : Color.folio.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))

                // Source citations
                if !message.sources.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        ForEach(message.sources, id: \.self) { source in
                            HStack(spacing: Spacing.xxs) {
                                Image(systemName: "doc.text")
                                    .font(.caption2)
                                    .foregroundStyle(Color.folio.accent)
                                Text(source)
                                    .font(Typography.caption)
                                    .foregroundStyle(Color.folio.link)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.xxs)
                }
            }

            if !message.isUser { Spacer(minLength: 60) }
        }
        .id(message.id)
    }

    // MARK: - Thinking Indicator

    private var thinkingIndicator: some View {
        HStack {
            HStack(spacing: Spacing.xs) {
                ProgressView()
                    .scaleEffect(0.7)
                Text(String(localized: "askai.thinking", defaultValue: "Searching your collection..."))
                    .font(Typography.caption)
                    .foregroundStyle(Color.folio.textTertiary)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(Color.folio.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
            Spacer()
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: Spacing.xs) {
            TextField(
                String(localized: "askai.placeholder", defaultValue: "Ask about your saved articles..."),
                text: $inputText,
                axis: .vertical
            )
            .font(Typography.body)
            .lineLimit(1...4)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(Color.folio.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .focused($isInputFocused)

            Button {
                sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(inputText.isEmpty ? Color.folio.textTertiary : Color.folio.accent)
            }
            .disabled(inputText.isEmpty)
        }
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.vertical, Spacing.xs)
        .background(.ultraThinMaterial)
    }

    // MARK: - Actions

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let userMsg = ChatMessage(content: text, isUser: true, sources: [])
        messages.append(userMsg)
        inputText = ""
        isThinking = true

        // Mock AI response after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isThinking = false
            let reply = ChatMessage(
                content: String(localized: "askai.mockReply", defaultValue: "This is a demo response. In the full version, AI will search across all your saved articles and synthesize an answer with source citations."),
                isUser: false,
                sources: ["RAG Best Practices Guide", "Vector Database Overview"]
            )
            messages.append(reply)
        }
    }
}

// MARK: - Model

private struct ChatMessage: Identifiable {
    let id = UUID()
    let content: String
    let isUser: Bool
    let sources: [String]

    static let mockConversation: [ChatMessage] = [
        ChatMessage(
            content: "What approaches to reducing LLM costs have I saved?",
            isUser: true,
            sources: []
        ),
        ChatMessage(
            content: "Based on 4 articles in your collection, here are the main approaches:\n\n1. **Prompt caching** - Reuse computed prefixes to cut input token costs by 60-90%\n2. **Model routing** - Use smaller models for simple tasks, reserve large models for complex ones\n3. **Batch API** - Group non-urgent requests for 50% discount\n4. **Fine-tuning** - Shorter prompts with fine-tuned models reduce per-call costs",
            isUser: false,
            sources: [
                "Practical Guide to LLM Cost Optimization",
                "Anthropic Prompt Caching Deep Dive",
                "When to Fine-tune vs Prompt Engineer",
                "Building Cost-Effective AI Products",
            ]
        ),
    ]
}

#Preview {
    NavigationStack {
        AskAIView()
    }
}
