import SwiftUI
import Nuke
import NukeUI

struct ArticleCardView: View {
    let article: Article
    var onRetry: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                    Text(article.displayTitle)
                        .font(Typography.listTitle)
                        .foregroundStyle(Color.folio.textPrimary)
                        .lineLimit(2)

                    // Summary (hide if same as title)
                    if let summary = article.summary,
                       summary != article.title {
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

            // Processing / Failed status bar
            if article.status == .processing {
                statusInfoBar(
                    icon: "arrow.trianglehead.2.counterclockwise",
                    text: String(localized: "article.status.processing", defaultValue: "AI is analyzing this article..."),
                    color: Color.folio.warning
                )
            } else if article.status == .failed {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.folio.error)
                    Text(article.fetchError ?? String(localized: "article.status.failed", defaultValue: "Processing failed"))
                        .font(Typography.caption)
                        .foregroundStyle(Color.folio.error)
                        .lineLimit(1)

                    Spacer()

                    if let onRetry {
                        Button {
                            onRetry()
                        } label: {
                            Text(String(localized: "article.retry", defaultValue: "Retry"))
                                .font(Typography.caption)
                                .foregroundStyle(Color.folio.accent)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, Spacing.xxs)
                .padding(.leading, Spacing.sm + 8) // align with content after badge
            } else if article.status == .pending && article.syncState == .pendingUpload {
                statusInfoBar(
                    icon: "arrow.up.icloud",
                    text: String(localized: "article.status.pendingUpload", defaultValue: "Waiting to upload..."),
                    color: Color.folio.textTertiary
                )
            }
        }
        .padding(.vertical, Spacing.xs)
        .padding(.horizontal, Spacing.screenPadding)
        .background(Color.folio.cardBackground)
    }

    private func statusInfoBar(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)
            Text(text)
                .font(Typography.caption)
                .foregroundStyle(color)
                .lineLimit(1)
            Spacer()
        }
        .padding(.top, Spacing.xxs)
        .padding(.leading, Spacing.sm + 8)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch article.status {
        case .pending:
            if article.syncState == .pendingUpload {
                StatusBadge(status: .pendingSync)
            } else if article.readProgress == 0 {
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
                    .accessibilityLabel("WeChat")
            case .twitter:
                Image(systemName: "bird")
                    .accessibilityLabel("Twitter")
            case .weibo:
                Image(systemName: "globe.asia.australia")
                    .accessibilityLabel("Weibo")
            case .zhihu:
                Image(systemName: "questionmark.circle")
                    .accessibilityLabel("Zhihu")
            case .youtube:
                Image(systemName: "play.rectangle.fill")
                    .accessibilityLabel("YouTube")
            case .newsletter:
                Image(systemName: "envelope.fill")
                    .accessibilityLabel("Newsletter")
            case .web:
                Image(systemName: "globe")
                    .accessibilityLabel("Web")
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
