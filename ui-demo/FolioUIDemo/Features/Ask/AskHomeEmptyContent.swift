import SwiftUI

struct AskHomeEmptyContent: View {
    let onTrustSuggestion: () -> Void
    let onReadingSuggestion: () -> Void
    let onPerformanceSuggestion: () -> Void

    var body: some View {
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
                    action: onTrustSuggestion
                )
                AskSuggestionButton(
                    symbol: "book.closed",
                    title: "我读过哪些关于深度阅读的观点？",
                    action: onReadingSuggestion
                )
                AskSuggestionButton(
                    symbol: "speedometer",
                    title: "SwiftUI 性能优化有哪些共同建议？",
                    action: onPerformanceSuggestion
                )
            }
            .padding(.top, 52)
            .padding(.bottom, 24)
        }
        .padding(.horizontal, FolioMetrics.libraryInset)
    }
}
