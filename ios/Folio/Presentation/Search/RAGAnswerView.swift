import SwiftUI

// MARK: - RAGAnswerView

struct RAGAnswerView: View {
    let thread: [(question: String, response: RAGQueryResponse)]
    let response: RAGQueryResponse
    let onSourceTap: (String) -> Void
    let onFollowup: (String) -> Void

    @State private var expandedSourceId: String?
    @State private var followupText = ""
    @State private var sourcesVisible = false
    @FocusState private var isFollowupFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 0. Previous Q&A thread
            if !thread.isEmpty {
                threadView
                    .padding(.bottom, 24)
            }

            // 1. Badge
            badgeView
                .padding(.bottom, 16)

            // 2. Answer body
            answerBodyView
                .padding(.bottom, 24)

            // 3. Sources section
            if !response.sources.isEmpty {
                sourcesSection
                    .padding(.bottom, 24)
                    .opacity(sourcesVisible ? 1 : 0)
                    .offset(y: sourcesVisible ? 0 : 8)
                    .onAppear {
                        withAnimation(Motion.ink.delay(0.3)) {
                            sourcesVisible = true
                        }
                    }
            }

            // 4. Follow-up suggestions
            if !response.followupSuggestions.isEmpty {
                followupSuggestionsSection
                    .padding(.bottom, 20)
            }

            // 5. Follow-up input
            followupInputView
        }
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.vertical, Spacing.lg)
    }

    // MARK: - Thread

    private var threadView: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(thread.enumerated()), id: \.offset) { _, pair in
                // User question (gray left border)
                HStack(alignment: .top, spacing: 0) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.folio.textQuaternary)
                        .frame(width: 2)
                    Text(pair.question)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.folio.textTertiary)
                        .padding(.leading, 12)
                }
                .padding(.bottom, 12)

                // AI answer (answer text only — no sources repeat)
                Text(pair.response.answer)
                    .font(Font.custom("LXGWWenKaiTC-Regular", size: 16))
                    .foregroundStyle(Color.folio.textPrimary)
                    .lineSpacing(16 * 0.75)
                    .padding(.bottom, 24)
            }
        }
    }

    // MARK: - Badge

    private var badgeView: some View {
        Text("\u{2726} \u{57FA}\u{4E8E} \(response.sourceCount) \u{7BC7}\u{6536}\u{85CF}")
            .font(.system(size: 11, weight: .medium))
            .tracking(1)
            .textCase(.uppercase)
            .foregroundStyle(Color.folio.accent)
    }

    // MARK: - Answer Body

    private var answerBodyView: some View {
        parseAnswerText(response.answer)
            .font(Font.custom("LXGWWenKaiTC-Regular", size: 16))
            .foregroundStyle(Color.folio.textPrimary)
            .lineSpacing(16 * 0.75)
    }

    /// Parses answer text, rendering **bold** and superscript citations.
    private func parseAnswerText(_ text: String) -> Text {
        var result = Text("")
        var remaining = text[text.startIndex...]

        while !remaining.isEmpty {
            // Look for next special pattern: **bold** or superscript citation
            if let boldRange = remaining.range(of: "**") {
                // Emit text before the bold marker
                let before = remaining[remaining.startIndex..<boldRange.lowerBound]
                result = result + parseCitations(String(before))

                // Find closing **
                let afterOpen = remaining[boldRange.upperBound...]
                if let closeRange = afterOpen.range(of: "**") {
                    let boldContent = afterOpen[afterOpen.startIndex..<closeRange.lowerBound]
                    result = result + Text(boldContent).bold()
                    remaining = afterOpen[closeRange.upperBound...]
                } else {
                    // No closing **, treat as literal
                    result = result + Text(String(remaining[remaining.startIndex..<boldRange.upperBound]))
                    remaining = remaining[boldRange.upperBound...]
                }
            } else {
                // No more bold markers, parse rest for citations
                result = result + parseCitations(String(remaining))
                break
            }
        }

        return result
    }

    /// Renders superscript citation markers (Unicode superscripts or [n] brackets).
    private func parseCitations(_ text: String) -> Text {
        let superscripts: [Character: String] = [
            "\u{00B9}": "1", "\u{00B2}": "2", "\u{00B3}": "3",
            "\u{2074}": "4", "\u{2075}": "5", "\u{2076}": "6",
            "\u{2077}": "7", "\u{2078}": "8", "\u{2079}": "9"
        ]

        var result = Text("")
        var buffer = ""

        var i = text.startIndex
        while i < text.endIndex {
            let ch = text[i]

            // Check for Unicode superscript digits
            if superscripts.keys.contains(ch) {
                if !buffer.isEmpty {
                    result = result + Text(buffer)
                    buffer = ""
                }
                result = result + Text(String(ch))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.folio.textTertiary)
                i = text.index(after: i)
                continue
            }

            // Check for [n] bracket citations
            if ch == "[" {
                let afterBracket = text.index(after: i)
                if afterBracket < text.endIndex {
                    // Look for closing bracket
                    if let closeBracket = text[afterBracket...].firstIndex(of: "]") {
                        let inner = text[afterBracket..<closeBracket]
                        if inner.allSatisfy(\.isNumber), !inner.isEmpty {
                            if !buffer.isEmpty {
                                result = result + Text(buffer)
                                buffer = ""
                            }
                            result = result + Text("[\(inner)]")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.folio.textTertiary)
                            i = text.index(after: closeBracket)
                            continue
                        }
                    }
                }
            }

            buffer.append(ch)
            i = text.index(after: i)
        }

        if !buffer.isEmpty {
            result = result + Text(buffer)
        }

        return result
    }

    // MARK: - Sources Section

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\u{6765}\u{6E90}\u{6587}\u{7AE0}")
                .font(.system(size: 14))
                .foregroundStyle(Color.folio.textSecondary)
                .padding(.top, 20)

            ForEach(response.sources, id: \.articleId) { source in
                sourceRow(source)
            }
        }
    }

    private func sourceRow(_ source: RAGSource) -> some View {
        Button {
            if expandedSourceId == source.articleId {
                onSourceTap(source.articleId)
            } else {
                withAnimation(Motion.quick) {
                    expandedSourceId = source.articleId
                }
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(Color.folio.accent)
                    .frame(width: 4, height: 4)
                    .padding(.top, 7)

                VStack(alignment: .leading, spacing: 2) {
                    Text(source.title)
                        .font(.system(size: 15, design: .serif))
                        .foregroundStyle(Color.folio.textPrimary)
                        .multilineTextAlignment(.leading)

                    Text(sourceMetaText(source))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.folio.textTertiary)

                    if expandedSourceId == source.articleId,
                       let summary = source.summary, !summary.isEmpty {
                        Text(summary)
                            .font(.system(size: 14))
                            .foregroundStyle(Color.folio.textSecondary)
                            .lineSpacing(4)
                            .padding(.top, 8)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func sourceMetaText(_ source: RAGSource) -> String {
        var parts: [String] = []
        if let siteName = source.siteName, !siteName.isEmpty {
            parts.append(siteName)
        }
        parts.append(formatSourceDate(source.createdAt))
        return parts.joined(separator: " \u{00B7} ")
    }

    // MARK: - Follow-up Suggestions

    private var followupSuggestionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(response.followupSuggestions, id: \.self) { suggestion in
                Button {
                    onFollowup(suggestion)
                } label: {
                    Text("\u{2192} \(suggestion)")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.folio.accent)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Follow-up Input

    private var followupInputView: some View {
        HStack(spacing: 10) {
            TextField("\u{7EE7}\u{7EED}\u{63D0}\u{95EE}\u{2026}", text: $followupText)
                .font(.system(size: 15))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.folio.echoBg)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .focused($isFollowupFocused)
                .onSubmit {
                    submitFollowup()
                }

            Button {
                submitFollowup()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(followupText.trimmingCharacters(in: .whitespaces).isEmpty
                                  ? Color.folio.accent.opacity(0.4)
                                  : Color.folio.accent)
                    )
            }
            .buttonStyle(.plain)
            .disabled(followupText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: - Helpers

    private func submitFollowup() {
        let trimmed = followupText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        followupText = ""
        isFollowupFocused = false
        onFollowup(trimmed)
    }

    private func formatSourceDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        fmt.dateFormat = "M\u{6708}d\u{65E5}\u{6536}\u{85CF}"
        return fmt.string(from: date)
    }
}

// MARK: - RAGLoadingView

struct RAGLoadingView: View {
    @State private var opacity = 0.4

    var body: some View {
        HStack(spacing: 8) {
            Text("\u{2726}")
                .foregroundStyle(Color.folio.accent)
            Text("\u{6B63}\u{5728}\u{601D}\u{8003}...")
                .foregroundStyle(Color.folio.textSecondary)
        }
        .font(.system(size: 15))
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .opacity(opacity)
        .onAppear {
            withAnimation(Motion.slow.repeatForever(autoreverses: true)) {
                opacity = 1.0
            }
        }
    }
}

// MARK: - RAGErrorView

struct RAGErrorView: View {
    enum ErrorType {
        case error
        case quota
        case noArticles
    }

    let errorType: ErrorType
    let onRetry: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Text(message)
                .font(.system(size: 15))
                .foregroundStyle(Color.folio.textSecondary)
                .multilineTextAlignment(.center)

            if let action = actionButton {
                Button {
                    action.action()
                } label: {
                    Text(action.label)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.folio.accent)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 24)
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.folio.accent.opacity(0.3), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .padding(.horizontal, Spacing.screenPadding)
    }

    private var message: String {
        switch errorType {
        case .error:
            return "\u{56DE}\u{7B54}\u{751F}\u{6210}\u{5931}\u{8D25}\u{FF0C}\u{8BF7}\u{91CD}\u{8BD5}\u{3002}"
        case .quota:
            return "\u{672C}\u{6708}\u{95EE}\u{7B54}\u{6B21}\u{6570}\u{5DF2}\u{7528}\u{5B8C}"
        case .noArticles:
            return "\u{5148}\u{6536}\u{85CF}\u{4E00}\u{4E9B}\u{6587}\u{7AE0}\u{518D}\u{6765}\u{63D0}\u{95EE}\u{5427}\u{3002}"
        }
    }

    private var actionButton: (label: String, action: () -> Void)? {
        switch errorType {
        case .error:
            guard let onRetry else { return nil }
            return ("\u{91CD}\u{8BD5}", onRetry)
        case .quota:
            return ("\u{5347}\u{7EA7} Pro", { /* handled by parent */ })
        case .noArticles:
            return nil
        }
    }
}
