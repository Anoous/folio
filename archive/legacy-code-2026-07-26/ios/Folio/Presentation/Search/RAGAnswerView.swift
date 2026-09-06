import SwiftUI

// MARK: - RAGAnswerView

struct RAGAnswerView: View {
    let thread: [RAGThreadEntry]
    let partialAnswer: String
    let sources: [RAGSource]
    let sourceCount: Int
    let citedIndices: [Int]
    let followupSuggestions: [String]
    let isStreaming: Bool
    let onSourceTap: (String) -> Void
    let onFollowup: (String) -> Void
    let onStop: () -> Void

    @State private var expandedSourceId: String?
    @State private var followupText = ""
    @State private var sourcesVisible = false
    @State private var cursorOpacity: Double = 1.0
    @FocusState private var isFollowupFocused: Bool

    private var citedSources: [RAGSource] {
        if citedIndices.isEmpty { return [] }
        return citedIndices.compactMap { idx in
            let arrayIdx = idx - 1
            guard arrayIdx >= 0, arrayIdx < sources.count else { return nil }
            return sources[arrayIdx]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !thread.isEmpty {
                threadView
                    .padding(.bottom, 24)
            }

            if sourceCount > 0 {
                badgeView
                    .padding(.bottom, 16)
            }

            if !partialAnswer.isEmpty {
                answerBodyView
                    .padding(.bottom, isStreaming ? 16 : 24)
            }

            if isStreaming {
                stopButton
                    .padding(.bottom, 24)
            }

            if !isStreaming && !citedSources.isEmpty {
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

            if !isStreaming && !followupSuggestions.isEmpty {
                followupSuggestionsSection
                    .padding(.bottom, 20)
            }

            if !isStreaming {
                followupInputView
            }
        }
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.vertical, Spacing.lg)
    }

    // MARK: - Thread

    private var threadView: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(thread.enumerated()), id: \.offset) { _, entry in
                HStack(alignment: .top, spacing: 0) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.folio.textQuaternary)
                        .frame(width: 2)
                    Text(entry.question)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.folio.textTertiary)
                        .padding(.leading, 12)
                }
                .padding(.bottom, 12)

                Text(entry.answer)
                    .font(Font.custom("LXGWWenKaiTC-Regular", size: 16))
                    .foregroundStyle(Color.folio.textPrimary)
                    .lineSpacing(16 * 0.75)
                    .padding(.bottom, 24)
            }
        }
    }

    // MARK: - Badge

    private var badgeView: some View {
        Text("\u{2726} 基于 \(sourceCount) 篇收藏")
            .font(.system(size: 11, weight: .medium))
            .tracking(1)
            .textCase(.uppercase)
            .foregroundStyle(Color.folio.accent)
    }

    // MARK: - Answer Body

    private var answerBodyView: some View {
        HStack(alignment: .bottom, spacing: 0) {
            parseAnswerText(partialAnswer)
                .font(Font.custom("LXGWWenKaiTC-Regular", size: 16))
                .foregroundStyle(Color.folio.textPrimary)
                .lineSpacing(16 * 0.75)

            if isStreaming {
                Text("|")
                    .font(Font.custom("LXGWWenKaiTC-Regular", size: 16))
                    .foregroundStyle(Color.folio.accent)
                    .opacity(cursorOpacity)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                            cursorOpacity = 0.0
                        }
                    }
                    .onDisappear {
                        cursorOpacity = 1.0
                    }
            }
        }
    }

    // MARK: - Stop Button

    private var stopButton: some View {
        HStack {
            Spacer()
            Button {
                onStop()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 10))
                    Text("停止生成")
                        .font(.system(size: 14))
                }
                .foregroundStyle(Color.folio.textSecondary)
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(Capsule().strokeBorder(Color.folio.textQuaternary, lineWidth: 1))
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }

    // MARK: - Sources Section

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("来源文章")
                .font(.system(size: 14))
                .foregroundStyle(Color.folio.textSecondary)
                .padding(.top, 20)

            ForEach(citedSources, id: \.articleId) { source in
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
                       let sourceText = sourceEvidenceText(source) {
                        Text(sourceText)
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

    private func sourceEvidenceText(_ source: RAGSource) -> String? {
        if let evidenceSnippet = source.evidenceSnippet, !evidenceSnippet.isEmpty {
            return evidenceSnippet
        }
        if let summary = source.summary, !summary.isEmpty {
            return summary
        }
        return nil
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
            ForEach(followupSuggestions, id: \.self) { suggestion in
                Button {
                    onFollowup(suggestion)
                } label: {
                    Text("→ \(suggestion)")
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
            TextField("继续提问…", text: $followupText)
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

    private static let sourceDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日收藏"
        return f
    }()

    private func formatSourceDate(_ date: Date) -> String {
        Self.sourceDateFormatter.string(from: date)
    }
}

// MARK: - RAGLoadingView

struct RAGLoadingView: View {
    @State private var opacity = 0.4

    var body: some View {
        HStack(spacing: 8) {
            Text("\u{2726}")
                .foregroundStyle(Color.folio.accent)
            Text("正在思考...")
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
            return "回答生成失败，请重试。"
        case .quota:
            return "本月问答次数已用完"
        case .noArticles:
            return "先收藏一些文章再来提问吧。"
        }
    }

    private var actionButton: (label: String, action: () -> Void)? {
        switch errorType {
        case .error:
            guard let onRetry else { return nil }
            return ("重试", onRetry)
        case .quota:
            return ("升级 Pro", { /* handled by parent */ })
        case .noArticles:
            return nil
        }
    }
}
