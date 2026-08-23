import SwiftUI

struct ReaderContentView: View {
    let article: DemoArticle
    let fontChoice: ReaderFontChoice
    let theme: ReaderTheme
    let highlights: [DemoHighlight]
    let onHighlight: (DemoTextSelection) -> Void
    let onAddNote: (DemoTextSelection) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(article.readerTitle)
                .font(fontChoice.emphasizedFont(28, relativeTo: .title))
                .foregroundStyle(theme.headingColor)
                .lineSpacing(8)
                .padding(.top, FolioMetrics.articleContentTopSpacing)
                .id("reader-title")

            ForEach(article.originalParagraphs.enumerated(), id: \.offset) { index, paragraph in
                SelectableReaderParagraph(
                    text: paragraph,
                    paragraphIndex: index,
                    highlights: highlights.filter { $0.paragraphIndex == index },
                    fontChoice: fontChoice,
                    theme: theme,
                    onHighlight: onHighlight,
                    onAddNote: onAddNote
                )
                    .padding(.top, index == 0 ? 25 : 26)
                    .id("reader-paragraph-\(index)")

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
                        .id("reader-pull-quote")
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
            theme: .paper,
            highlights: [],
            onHighlight: { _ in },
            onAddNote: { _ in }
        )
            .padding(.horizontal, FolioMetrics.readingInset)
    }
    .background(ReaderTheme.paper.backgroundColor)
}
