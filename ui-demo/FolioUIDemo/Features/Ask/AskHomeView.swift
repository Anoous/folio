import SwiftUI

struct AskHomeView: View {
    let onOpenSettings: () -> Void
    let onAnswer: () -> Void
    let onInsufficientEvidence: () -> Void
    @State private var question = ""

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("问 Folio")
                    .font(.headline)

                HStack {
                    Color.clear
                        .frame(width: FolioMetrics.minimumTapTarget, height: FolioMetrics.minimumTapTarget)

                    Spacer()

                    Button(action: onOpenSettings) {
                        FolioAvatar(size: FolioMetrics.minimumTapTarget)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("打开设置")
                }
            }
            .padding(.horizontal, FolioMetrics.libraryInset)
            .padding(.top, 8)
            .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(FolioPalette.inkGreenDeep)
                            .frame(width: 48, height: 48)
                            .background(FolioPalette.subtleGreen)
                            .clipShape(.circle)
                            .accessibilityHidden(true)

                        Text("问问你的收藏")
                            .font(.title2.bold())
                            .foregroundStyle(FolioPalette.inkGreenDeep)

                        Text("答案只来自你保存的内容，并附上来源。")
                            .font(.subheadline)
                            .foregroundStyle(FolioPalette.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 58)

                    VStack(spacing: 4) {
                        AskSuggestionButton(
                            symbol: "checkmark.shield",
                            title: "我保存的内容如何定义 AI 可信度？",
                            action: onAnswer
                        )
                        AskSuggestionButton(
                            symbol: "book.closed",
                            title: "我读过哪些关于深度阅读的观点？",
                            action: onAnswer
                        )
                        AskSuggestionButton(
                            symbol: "speedometer",
                            title: "SwiftUI 性能优化有哪些共同建议？",
                            action: onInsufficientEvidence
                        )
                    }
                    .padding(.top, 52)
                    .padding(.bottom, 24)
                }
                .padding(.horizontal, FolioMetrics.libraryInset)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)

            FolioInputBar(
                text: $question,
                placeholder: "问问你的收藏",
                isEnabled: hasQuestion,
                action: submitQuestion
            )
            .padding(.horizontal, FolioMetrics.libraryInset)
            .padding(.vertical, 10)
        }
        .background(FolioPalette.canvas)
        .toolbar(.hidden, for: .navigationBar)
    }

    private func submitQuestion() {
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if question.localizedStandardContains("行业") || question.localizedStandardContains("SwiftUI") {
            onInsufficientEvidence()
        } else {
            onAnswer()
        }
    }

    private var hasQuestion: Bool {
        !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

#Preview {
    AskHomeView(onOpenSettings: {}, onAnswer: {}, onInsufficientEvidence: {})
        .safeAreaInset(edge: .bottom, spacing: 0) {
            FolioTabBar(
                selectedTab: .constant(.ask)
            )
            .padding(.horizontal, FolioMetrics.compactInset)
            .padding(.vertical, 8)
        }
}
