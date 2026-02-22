import SwiftUI

/// Displays article metadata in a card: source, date, category, tags,
/// word count, and estimated reading time.
struct ArticleMetaInfoView: View {
    let article: Article
    let wordCount: Int
    let readingTimeMinutes: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Source + Date row
            HStack(spacing: Spacing.xs) {
                sourceIcon
                if let siteName = article.siteName {
                    Text(siteName)
                        .font(Typography.caption)
                        .foregroundStyle(Color.folio.textSecondary)
                }

                if let author = article.author {
                    Text("\u{00B7}")
                        .foregroundStyle(Color.folio.textTertiary)
                    Text(author)
                        .font(Typography.caption)
                        .foregroundStyle(Color.folio.textSecondary)
                }

                Spacer()

                if let publishedAt = article.publishedAt {
                    Text(publishedAt.relativeFormatted())
                        .font(Typography.caption)
                        .foregroundStyle(Color.folio.textTertiary)
                } else {
                    Text(article.createdAt.relativeFormatted())
                        .font(Typography.caption)
                        .foregroundStyle(Color.folio.textTertiary)
                }
            }

            // Category
            if let category = article.category {
                HStack(spacing: Spacing.xxs) {
                    Text(category.icon)
                        .font(Typography.caption)
                    Text(category.localizedName)
                        .font(Typography.caption)
                        .foregroundStyle(Color.folio.accent)
                }
            }

            // Tags
            if !article.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.xxs) {
                        ForEach(article.tags) { tag in
                            TagChip(text: tag.name)
                        }
                    }
                }
            }

            // Word count + reading time
            HStack(spacing: Spacing.sm) {
                Label {
                    Text(formattedWordCount)
                        .font(Typography.caption)
                        .foregroundStyle(Color.folio.textTertiary)
                } icon: {
                    Image(systemName: "text.word.spacing")
                        .font(.caption2)
                        .foregroundStyle(Color.folio.textTertiary)
                }

                Label {
                    Text(formattedReadingTime)
                        .font(Typography.caption)
                        .foregroundStyle(Color.folio.textTertiary)
                } icon: {
                    Image(systemName: "clock")
                        .font(.caption2)
                        .foregroundStyle(Color.folio.textTertiary)
                }
            }
        }
        .padding(Spacing.md)
        .background(Color.folio.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.medium)
                .stroke(Color.folio.separator, lineWidth: 0.5)
        )
    }

    // MARK: - Source Icon

    private var sourceIcon: some View {
        Group {
            switch article.sourceType {
            case .wechat:
                Image(systemName: "message.fill").accessibilityLabel("WeChat")
            case .twitter:
                Image(systemName: "bird").accessibilityLabel("Twitter")
            case .weibo:
                Image(systemName: "globe.asia.australia").accessibilityLabel("Weibo")
            case .zhihu:
                Image(systemName: "questionmark.circle").accessibilityLabel("Zhihu")
            case .youtube:
                Image(systemName: "play.rectangle.fill").accessibilityLabel("YouTube")
            case .newsletter:
                Image(systemName: "envelope.fill").accessibilityLabel("Newsletter")
            case .web:
                Image(systemName: "globe").accessibilityLabel("Web")
            }
        }
        .font(.caption2)
        .foregroundStyle(Color.folio.textSecondary)
    }

    // MARK: - Formatting

    private var formattedWordCount: String {
        if wordCount >= 10_000 {
            let value = Double(wordCount) / 10_000
            return String(format: "%.1f", value) + "w"
        }
        return "\(wordCount) " + String(localized: "meta.chars", defaultValue: "chars")
    }

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
        wordCount: 2400,
        readingTimeMinutes: 6
    )
    .padding()
}
