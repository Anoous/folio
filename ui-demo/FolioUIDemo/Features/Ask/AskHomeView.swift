import SwiftUI

struct AskHomeView: View {
    let onOpenSettings: () -> Void
    let onAnswer: () -> Void
    let onInsufficientEvidence: () -> Void
    @State private var question = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("提问")
                            .font(FolioTypography.editorialBold(43, relativeTo: .largeTitle))
                            .foregroundStyle(FolioPalette.inkGreenDeep)

                        Spacer()

                        Button(action: onOpenSettings) {
                            FolioAvatar(size: 48)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("打开设置")
                    }
                    .padding(.top, 48)

                    VStack(spacing: 17) {
                        Image(systemName: "questionmark.bubble")
                            .font(.system(size: 66, weight: .light))
                            .foregroundStyle(FolioPalette.inkGreenDeep)
                            .accessibilityHidden(true)

                        Text("问问你保存过的内容")
                            .font(FolioTypography.editorialBold(23, relativeTo: .title2))
                            .foregroundStyle(FolioPalette.inkGreenDeep)

                        Text("Folio 只根据你的资料回答，并附上来源。\n资料不足时，会明确说明。")
                            .font(.system(size: 16))
                            .foregroundStyle(FolioPalette.secondaryText)
                            .multilineTextAlignment(.center)
                            .lineSpacing(7)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 74)

                    VStack(spacing: 12) {
                        AskSuggestionButton(
                            title: "我保存的内容如何定义 AI 可信度？",
                            action: onAnswer
                        )
                        AskSuggestionButton(
                            title: "我读过哪些关于深度阅读的观点？",
                            action: onAnswer
                        )
                        AskSuggestionButton(
                            title: "SwiftUI 性能优化有哪些共同建议？",
                            action: onInsufficientEvidence
                        )
                    }
                    .padding(.top, 47)
                    .padding(.bottom, 30)
                }
                .padding(.horizontal, FolioMetrics.pageInset)
            }
            .scrollIndicators(.hidden)

            FolioInputBar(
                text: $question,
                placeholder: "输入你的问题…",
                isEnabled: true,
                action: submitQuestion
            )
            .padding(.horizontal, FolioMetrics.pageInset)
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
}

#Preview {
    @Previewable @Namespace var transitionNamespace

    AskHomeView(onOpenSettings: {}, onAnswer: {}, onInsufficientEvidence: {})
        .safeAreaInset(edge: .bottom, spacing: 0) {
            FolioTabBar(
                selectedTab: .constant(.ask),
                navigationNamespace: transitionNamespace
            )
            .padding(.horizontal, FolioMetrics.compactInset)
            .padding(.vertical, 8)
        }
}
