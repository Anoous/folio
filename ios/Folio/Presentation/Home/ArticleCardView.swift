import SwiftUI
import NukeUI

struct ArticleCardView: View {
    let article: Article
    var onRetry: (() -> Void)?

    private var isUnread: Bool {
        article.readProgress == 0 && article.status == .ready
    }

    private var isFailed: Bool {
        article.status == .failed
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            // Unread dot
            if isUnread {
                Circle()
                    .fill(Color.folio.unread)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6) // align with first line of title
                    .accessibilityLabel(Text(String(localized: "status.unread", defaultValue: "Unread")))
            }

            VStack(alignment: .leading, spacing: 0) {
                // Title
                Text(article.displayTitle)
                    .font(Typography.listTitle)
                    .foregroundStyle(isFailed ? Color.folio.textSecondary : Color.folio.textPrimary)
                    .lineLimit(2)

                // Summary
                if let summary = article.displaySummary {
                    Text(summary)
                        .font(Typography.body)
                        .foregroundStyle(Color.folio.textSecondary)
                        .lineLimit(2)
                        .padding(.top, Spacing.xxs)
                }

                // Source line
                sourceLine
                    .padding(.top, Spacing.xs)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.sm)
    }

    // MARK: - Source Line

    private var sourceLine: some View {
        HStack(spacing: Spacing.xxs) {
            // Favicon
            faviconView

            // Source name
            if let siteName = article.siteName, !siteName.isEmpty {
                Text(siteName)
                    .font(Typography.tag)
                    .foregroundStyle(Color.folio.textTertiary)

                Text("\u{00B7}")
                    .foregroundStyle(Color.folio.textTertiary)
            }

            // Category
            if let category = article.category {
                Text(category.localizedName)
                    .font(Typography.caption)
                    .foregroundStyle(Color.folio.textTertiary)

                Text("\u{00B7}")
                    .foregroundStyle(Color.folio.textTertiary)
            }

            // Time
            Text(article.createdAt.relativeFormatted())
                .font(Typography.caption)
                .foregroundStyle(Color.folio.textTertiary)

            Spacer(minLength: 0)

            // Status icon (trailing)
            statusIcon

            // Favorite heart (trailing)
            if article.isFavorite {
                Image(systemName: "heart.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.pink)
                    .accessibilityLabel(Text(String(localized: "status.favorited", defaultValue: "Favorited")))
            }
        }
    }

    // MARK: - Favicon

    @ViewBuilder
    private var faviconView: some View {
        if let faviconURL = article.faviconURL, let url = URL(string: faviconURL) {
            LazyImage(url: url) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    // Loading or failure: show SF Symbol fallback
                    sourceTypeIcon
                }
            }
            .frame(width: 20, height: 20)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
        } else {
            sourceTypeIcon
        }
    }

    private var sourceTypeIcon: some View {
        Image(systemName: article.sourceType.iconName)
            .font(.system(size: 13))
            .foregroundStyle(Color.folio.textTertiary)
            .frame(width: 20, height: 20)
            .accessibilityLabel(article.sourceType.displayName)
    }

    // MARK: - Status Icon

    @ViewBuilder
    private var statusIcon: some View {
        switch article.status {
        case .processing:
            Image(systemName: "circle.dashed")
                .font(.system(size: 12))
                .foregroundStyle(Color.folio.warning)
                .symbolEffect(.variableColor.iterative)
                .accessibilityLabel(Text(String(localized: "status.processing", defaultValue: "Processing")))
        case .clientReady:
            Image(systemName: "doc.richtext")
                .font(.system(size: 12))
                .foregroundStyle(Color.folio.success)
                .accessibilityLabel(Text(String(localized: "status.clientReady", defaultValue: "Content ready")))
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Color.folio.error)
                .accessibilityLabel(Text(String(localized: "status.failed", defaultValue: "Failed")))
        case .pending where article.syncState == .pendingUpload:
            Image(systemName: "arrow.up.icloud")
                .font(.system(size: 12))
                .foregroundStyle(Color.folio.textTertiary)
                .accessibilityLabel(Text(String(localized: "status.pendingSync", defaultValue: "Pending sync")))
        default:
            EmptyView()
        }
    }
}

#Preview("Standard") {
    List {
        ArticleCardView(article: {
            let a = Article(url: "https://example.com", title: "SwiftUI Best Practices for 2025", sourceType: .web)
            a.siteName = "Swift Blog"
            a.summary = "A comprehensive guide to modern SwiftUI patterns and architecture decisions that will change how you build apps."
            return a
        }())
        ArticleCardView(article: {
            let a = Article(url: "https://mp.weixin.qq.com/s/abc", title: "Deep Dive into Swift Concurrency", sourceType: .wechat)
            a.siteName = "SwiftGG"
            a.summary = "Understanding actors, async/await, and structured concurrency in Swift 5.9."
            a.statusRaw = ArticleStatus.processing.rawValue
            return a
        }())
        ArticleCardView(article: {
            let a = Article(url: "https://x.com/user/status/123", title: "Claude Code is amazing", sourceType: .twitter)
            a.siteName = "Yanhua on X"
            a.statusRaw = ArticleStatus.ready.rawValue
            a.isFavorite = true
            return a
        }())
        ArticleCardView(article: {
            let a = Article(url: "https://example.com/fail", title: "Failed Article", sourceType: .web)
            a.statusRaw = ArticleStatus.failed.rawValue
            a.fetchError = "Network timeout"
            return a
        }())
    }
    .listStyle(.plain)
}
