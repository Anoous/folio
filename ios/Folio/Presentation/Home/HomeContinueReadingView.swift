import SwiftUI

struct HomeContinueReadingView: View {
    let continueArticles: [Article]
    let suggestedArticles: [Article]
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 72)
            } else if !continueArticles.isEmpty {
                ForEach(continueArticles) { article in
                    HomeArticlePreviewRow(
                        article: article,
                        subtitle: continueSubtitle(for: article),
                        showsProgress: true
                    )
                }
            } else if !suggestedArticles.isEmpty {
                ForEach(suggestedArticles) { article in
                    HomeArticlePreviewRow(
                        article: article,
                        subtitle: suggestedSubtitle(for: article),
                        showsProgress: false
                    )
                }
            } else {
                ContentUnavailableView(
                    "暂无可读内容",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("捕获的内容完成处理后，会出现在这里。")
                )
                .frame(maxWidth: .infinity, minHeight: 118)
            }
        }
        .padding(.horizontal, Spacing.screenPadding)
    }

    private func continueSubtitle(for article: Article) -> String {
        let progress = max(Int(article.readProgress * 100), 1)
        let source = article.effectiveSourceName ?? article.sourceType.displayName
        return "\(source) · 已读 \(progress)%"
    }

    private func suggestedSubtitle(for article: Article) -> String {
        var parts: [String] = []
        if let source = article.effectiveSourceName {
            parts.append(source)
        }
        parts.append(article.createdAt.relativeFormatted())
        if article.wordCount > 0 {
            parts.append("\(article.wordCount) 字")
        }
        return parts.joined(separator: " · ")
    }
}
