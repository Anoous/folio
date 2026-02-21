import SwiftUI
import Nuke
import NukeUI

struct ArticleCardView: View {
    let article: Article

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            // Status badge
            statusBadge

            // Thumbnail
            if let coverURL = article.coverImageURL, let url = URL(string: coverURL) {
                LazyImage(url: url) { state in
                    if let image = state.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Color.folio.separator
                    }
                }
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
            }

            // Content
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                // Title
                Text(article.title ?? article.url)
                    .font(Typography.listTitle)
                    .foregroundStyle(Color.folio.textPrimary)
                    .lineLimit(2)

                // Summary
                if let summary = article.summary {
                    Text(summary)
                        .font(Typography.body)
                        .foregroundStyle(Color.folio.textSecondary)
                        .lineLimit(2)
                }

                // Source + time
                HStack(spacing: Spacing.xxs) {
                    sourceIcon
                    if let siteName = article.siteName {
                        Text(siteName)
                            .font(Typography.caption)
                            .foregroundStyle(Color.folio.textTertiary)
                    }
                    Text("·")
                        .foregroundStyle(Color.folio.textTertiary)
                    Text(article.createdAt.relativeFormatted())
                        .font(Typography.caption)
                        .foregroundStyle(Color.folio.textTertiary)
                }

                // Tags (max 3)
                if !article.tags.isEmpty {
                    HStack(spacing: Spacing.xxs) {
                        ForEach(article.tags.prefix(3)) { tag in
                            TagChip(text: tag.name)
                        }
                        if article.tags.count > 3 {
                            Text("+\(article.tags.count - 3)")
                                .font(Typography.tag)
                                .foregroundStyle(Color.folio.textTertiary)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.xs)
        .padding(.horizontal, Spacing.screenPadding)
        .background(Color.folio.cardBackground)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch article.status {
        case .pending:
            if article.readProgress == 0 {
                StatusBadge(status: .unread)
            }
        case .processing:
            StatusBadge(status: .processing)
        case .failed:
            StatusBadge(status: .failed)
        case .ready:
            if article.readProgress == 0 {
                StatusBadge(status: .unread)
            }
        }
    }

    private var sourceIcon: some View {
        Group {
            switch article.sourceType {
            case .wechat:
                Image(systemName: "message.fill")
            case .twitter:
                Image(systemName: "bird")
            case .weibo:
                Image(systemName: "globe.asia.australia")
            case .zhihu:
                Image(systemName: "questionmark.circle")
            case .youtube:
                Image(systemName: "play.rectangle.fill")
            case .newsletter:
                Image(systemName: "envelope.fill")
            case .web:
                Image(systemName: "globe")
            }
        }
        .font(.caption2)
        .foregroundStyle(Color.folio.textTertiary)
    }
}

#Preview {
    VStack(spacing: 0) {
        ArticleCardView(article: {
            let a = Article(url: "https://example.com", title: "SwiftUI Best Practices for 2025", sourceType: .web)
            a.summary = "A comprehensive guide to building modern iOS applications with SwiftUI."
            a.siteName = "Swift Blog"
            return a
        }())
        Divider()
        ArticleCardView(article: {
            let a = Article(url: "https://mp.weixin.qq.com/s/abc", title: "深入理解 Swift 并发模型", sourceType: .wechat)
            a.summary = "本文详细介绍了 Swift 的 async/await 并发编程模型。"
            a.siteName = "SwiftGG"
            a.statusRaw = ArticleStatus.processing.rawValue
            return a
        }())
    }
}
