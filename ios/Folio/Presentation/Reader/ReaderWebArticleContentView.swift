import SwiftUI

struct ReaderWebArticleContentView: View {
    let article: Article
    var viewModel: ReaderViewModel
    let fontSize: Double
    let lineSpacing: Double
    let readingFontFamily: ReadingFontFamily
    let readingTheme: ReadingTheme
    let onImageTap: (String) -> Void
    let onLinkTap: (String) -> Void
    let onContentReady: () -> Void

    var body: some View {
        ArticleWebView(
            htmlContent: MarkdownToHTML.convertWithHeader(
                markdown: article.markdownContent ?? "",
                header: articleHeader,
                highlights: highlightTuples,
                fontSize: CGFloat(fontSize),
                lineSpacing: CGFloat(lineSpacing),
                fontFamily: readingFontFamily,
                theme: readingTheme,
                strings: .reader
            ),
            initialProgress: article.readProgress,
            fontSize: CGFloat(fontSize),
            lineSpacing: CGFloat(lineSpacing),
            fontFamily: readingFontFamily.cssName,
            themeBg: readingTheme.bgHex,
            themeText: readingTheme.textHex,
            themeSecondary: readingTheme.secondaryTextHex,
            onHighlightCreate: { text, start, end in
                viewModel.createHighlight(text: text, startOffset: start, endOffset: end)
            },
            onHighlightRemove: { id in
                viewModel.deleteHighlight(id: id)
            },
            onScrollProgress: { progress in
                viewModel.updateReadingProgress(progress)
            },
            onImageTap: onImageTap,
            onLinkTap: onLinkTap,
            onToast: { message in
                viewModel.showToastMessage(message, icon: nil)
            },
            onContentReady: onContentReady,
            onTitleVisibilityChange: nil
        )
    }

    private var highlightTuples: [(id: String, startOffset: Int, endOffset: Int)] {
        viewModel.highlights.map {
            (id: $0.id, startOffset: $0.startOffset, endOffset: $0.endOffset)
        }
    }

    private var articleHeader: MarkdownToHTML.ArticleHeader {
        let readingTime: String
        if viewModel.estimatedReadTimeMinutes < 1 {
            readingTime = String(localized: "meta.readTimeLess1", defaultValue: "< 1 min read")
        } else {
            readingTime = "~\(viewModel.estimatedReadTimeMinutes) " + String(localized: "meta.minRead", defaultValue: "min read")
        }

        let dateLabel = (article.publishedAt ?? article.createdAt).relativeFormatted()
        return MarkdownToHTML.ArticleHeader(
            title: article.displayTitle,
            siteName: article.siteName,
            author: article.author,
            readingTime: readingTime,
            dateLabel: dateLabel,
            summary: article.displaySummary,
            keyPoints: article.keyPoints
        )
    }
}
