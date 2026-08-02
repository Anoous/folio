import SwiftUI

struct InsightContentView: View {
    let article: DemoArticle
    let onShowEvidence: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FolioSectionTitle(title: "核心洞察")
                .padding(.top, FolioMetrics.articleContentTopSpacing)

            Text(article.insight)
                .font(FolioTypography.editorial(21.5, relativeTo: .title2))
                .foregroundStyle(FolioPalette.inkGreenDeep)
                .lineSpacing(9)
                .padding(.top, 24)

            Divider()
                .foregroundStyle(FolioPalette.paperLine)
                .padding(.vertical, 24)

            FolioSectionTitle(title: "关键观点")

            VStack(spacing: 10) {
                ForEach(Array(article.insightPoints.enumerated()), id: \.offset) { index, point in
                    InsightPointRow(
                        number: index + 1,
                        text: point,
                        citation: "[\(index + 1)]",
                        action: onShowEvidence
                    )
                }
            }
            .padding(.top, 20)

            Divider()
                .foregroundStyle(FolioPalette.paperLine)
                .padding(.top, 20)

            InsightFeedbackView()
                .padding(.vertical, 18)
        }
    }
}

#Preview {
    ScrollView {
        InsightContentView(article: DemoContent.primaryArticle, onShowEvidence: {})
            .padding(.horizontal, FolioMetrics.pageInset)
    }
    .background(FolioPalette.canvas)
}
