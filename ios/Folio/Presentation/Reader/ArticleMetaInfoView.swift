import SwiftUI

/// Displays article metadata as a single inline row:
/// siteName · author · reading time (left), relative date (right).
struct ArticleMetaInfoView: View {
    let article: Article
    let readingTimeMinutes: Int
    let textColor: Color

    var body: some View {
        HStack(spacing: Spacing.xs) {
            // Left side: siteName · author · reading time
            HStack(spacing: Spacing.xxs) {
                if let siteName = article.siteName {
                    Text(siteName)
                        .font(Typography.caption)
                        .foregroundStyle(textColor)
                }

                if article.siteName != nil, article.author != nil {
                    Text("\u{00B7}")
                        .foregroundStyle(textColor.opacity(0.6))
                }

                if let author = article.author {
                    Text(author)
                        .font(Typography.caption)
                        .foregroundStyle(textColor)
                }

                if article.siteName != nil || article.author != nil {
                    Text("\u{00B7}")
                        .foregroundStyle(textColor.opacity(0.6))
                }

                Text(formattedReadingTime)
                    .font(Typography.caption)
                    .foregroundStyle(textColor)
            }
            .lineLimit(1)

            Spacer()

            // Right side: relative date
            if let publishedAt = article.publishedAt {
                Text(publishedAt.relativeFormatted())
                    .font(Typography.caption)
                    .foregroundStyle(textColor.opacity(0.6))
            } else {
                Text(article.createdAt.relativeFormatted())
                    .font(Typography.caption)
                    .foregroundStyle(textColor.opacity(0.6))
            }
        }
    }

    // MARK: - Formatting

    private var formattedReadingTime: String {
        if readingTimeMinutes < 1 {
            return String(localized: "meta.readTimeLess1", defaultValue: "< 1 min read")
        }
        return "~\(readingTimeMinutes) " + String(localized: "meta.minRead", defaultValue: "min read")
    }
}

#Preview {
    let article = Article(url: "https://example.com", title: "Sample Article", sourceType: .web)
    article.siteName = "Example Blog"
    article.author = "John Doe"

    return ArticleMetaInfoView(
        article: article,
        readingTimeMinutes: 6,
        textColor: Color.folio.textSecondary
    )
    .padding()
}
