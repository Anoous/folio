import SwiftUI

struct InsightContentView: View {
    let article: DemoArticle
    let fontChoice: ReaderFontChoice
    let theme: ReaderTheme
    let onShowEvidence: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FolioSectionTitle(
                title: "核心洞察",
                font: fontChoice.emphasizedFont(18, relativeTo: .headline),
                foregroundStyle: theme.headingColor
            )
                .padding(.top, FolioMetrics.articleContentTopSpacing)

            Text(article.insight)
                .font(fontChoice.regularFont(21.5, relativeTo: .title2))
                .foregroundStyle(theme.headingColor)
                .lineSpacing(9)
                .padding(.top, 24)
                .accessibilityIdentifier("insight-body")
                .accessibilityValue("\(theme.title)，\(fontChoice.title)")

            Divider()
                .foregroundStyle(FolioPalette.paperLine)
                .padding(.vertical, 24)

            FolioSectionTitle(
                title: "关键观点",
                font: fontChoice.emphasizedFont(18, relativeTo: .headline),
                foregroundStyle: theme.headingColor
            )

            VStack(spacing: 10) {
                ForEach(Array(article.insightPoints.enumerated()), id: \.offset) { index, point in
                    InsightPointRow(
                        number: index + 1,
                        text: point,
                        citation: "[\(index + 1)]",
                        fontChoice: fontChoice,
                        theme: theme,
                        action: onShowEvidence
                    )
                }
            }
            .padding(.top, 20)
            .padding(.bottom, 36)
        }
    }
}

#Preview {
    ScrollView {
        InsightContentView(
            article: DemoContent.primaryArticle,
            fontChoice: .notoSerif,
            theme: .paper,
            onShowEvidence: {}
        )
            .padding(.horizontal, FolioMetrics.pageInset)
    }
    .background(ReaderTheme.paper.backgroundColor)
}
