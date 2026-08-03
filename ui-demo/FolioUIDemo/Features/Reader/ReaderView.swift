import SwiftUI

struct ReaderContentView: View {
    let article: DemoArticle
    let fontChoice: ReaderFontChoice
    let theme: ReaderTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(article.readerTitle)
                .font(fontChoice.emphasizedFont(28, relativeTo: .title))
                .foregroundStyle(theme.headingColor)
                .lineSpacing(8)
                .padding(.top, FolioMetrics.articleContentTopSpacing)

            ForEach(Array(article.originalParagraphs.enumerated()), id: \.offset) { index, paragraph in
                ReaderParagraph(text: paragraph, fontChoice: fontChoice, theme: theme)
                    .padding(.top, index == 0 ? 25 : 26)

                if index == 1 {
                    Text(article.pullQuote)
                        .font(fontChoice.regularFont(18, relativeTo: .body))
                        .foregroundStyle(theme.textColor)
                        .lineSpacing(9)
                        .padding(20)
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(theme.quoteRuleColor)
                                .frame(width: 2)
                        }
                        .background(theme.quoteBackgroundColor)
                        .clipShape(.rect(cornerRadius: 12))
                        .padding(.top, 25)
                }
            }
            .padding(.bottom, 30)
        }
    }
}

#Preview {
    ScrollView {
        ReaderContentView(
            article: DemoContent.primaryArticle,
            fontChoice: .notoSerif,
            theme: .paper
        )
            .padding(.horizontal, FolioMetrics.readingInset)
    }
    .background(ReaderTheme.paper.backgroundColor)
}
