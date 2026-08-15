import SwiftUI

struct AskHomeEmptyContent: View {
    let onTrustSuggestion: () -> Void
    let onReadingSuggestion: () -> Void
    let onPerformanceSuggestion: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(FolioPalette.inkGreenDeep)
                    .frame(width: 48, height: 48)
                    .background(FolioPalette.subtleGreen)
                    .clipShape(.circle)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text("问问你的收藏")
                        .font(FolioTypography.editorialBold(22, relativeTo: .title2))
                        .foregroundStyle(FolioPalette.inkGreenDeep)

                    Text("答案只来自你保存的内容，并附上来源。")
                        .font(.subheadline)
                        .foregroundStyle(FolioPalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 16)
            .accessibilityElement(children: .combine)

            Text("可以这样问")
                .font(FolioTypography.editorialBold(17, relativeTo: .headline))
                .foregroundStyle(FolioPalette.inkGreenDeep)
                .padding(.top, 32)
                .padding(.bottom, 4)

            VStack(spacing: 0) {
                AskSuggestionButton(
                    symbol: "checkmark.shield",
                    title: "我保存的内容如何定义 AI 可信度？",
                    action: onTrustSuggestion
                )

                Rectangle()
                    .fill(FolioPalette.paperLine.opacity(0.72))
                    .frame(height: 0.6)

                AskSuggestionButton(
                    symbol: "book.closed",
                    title: "我读过哪些关于深度阅读的观点？",
                    action: onReadingSuggestion
                )

                Rectangle()
                    .fill(FolioPalette.paperLine.opacity(0.72))
                    .frame(height: 0.6)

                AskSuggestionButton(
                    symbol: "speedometer",
                    title: "SwiftUI 性能优化有哪些共同建议？",
                    action: onPerformanceSuggestion
                )

                Rectangle()
                    .fill(FolioPalette.paperLine.opacity(0.72))
                    .frame(height: 0.6)
            }
            .padding(.bottom, 24)
        }
        .padding(.horizontal, FolioMetrics.libraryInset)
    }
}
