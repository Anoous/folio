import SwiftUI

struct ArticleCardView: View {
    let article: Article
    var onRetry: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: Spacing.xs) {
                statusBadge

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(article.displayTitle)
                        .font(Typography.listTitle)
                        .foregroundStyle(Color.folio.textPrimary)
                        .lineLimit(2)

                    if let summary = article.displaySummary {
                        Text(summary)
                            .font(Typography.caption)
                            .foregroundStyle(Color.folio.textSecondary)
                            .lineLimit(1)
                    }

                    HStack(spacing: Spacing.xxs) {
                        sourceIcon
                        if let siteName = article.siteName {
                            Text(siteName)
                                .font(Typography.caption)
                                .foregroundStyle(Color.folio.textTertiary)
                        }
                        Text("\u{00B7}")
                            .foregroundStyle(Color.folio.textTertiary)
                        Text(article.createdAt.relativeFormatted())
                            .font(Typography.caption)
                            .foregroundStyle(Color.folio.textTertiary)
                    }
                }

                Spacer(minLength: 0)
            }

            // Status bar for non-ready states
            switch article.status {
            case .processing:
                statusInfoBar(
                    icon: "arrow.trianglehead.2.counterclockwise",
                    text: String(localized: "article.status.processing", defaultValue: "AI is analyzing..."),
                    color: Color.folio.warning
                )
            case .failed:
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
            case .clientReady:
                statusInfoBar(
                    icon: "doc.richtext",
                    text: String(localized: "article.status.clientReady", defaultValue: "Content ready, AI analyzing..."),
                    color: Color.folio.success
                )
            case .pending where article.syncState == .pendingUpload:
                statusInfoBar(
                    icon: "arrow.up.icloud",
                    text: String(localized: "article.status.pendingUpload", defaultValue: "Waiting to upload..."),
                    color: Color.folio.textTertiary
                )
            default:
                EmptyView()
            }
        }
        .padding(.vertical, Spacing.xs)
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
        case .clientReady:
            StatusBadge(status: .clientReady)
        }
    }

    private var sourceIcon: some View {
        Image(systemName: article.sourceType.iconName)
            .font(.caption2)
            .foregroundStyle(Color.folio.textTertiary)
            .accessibilityLabel(article.sourceType.displayName)
    }
}

#Preview {
    VStack(spacing: 0) {
        ArticleCardView(article: {
            let a = Article(url: "https://example.com", title: "SwiftUI Best Practices for 2025", sourceType: .web)
            a.siteName = "Swift Blog"
            a.summary = "A comprehensive guide to modern SwiftUI patterns and architecture decisions."
            return a
        }())
        Divider()
        ArticleCardView(article: {
            let a = Article(url: "https://mp.weixin.qq.com/s/abc", title: "Deep Dive into Swift Concurrency", sourceType: .wechat)
            a.siteName = "SwiftGG"
            a.statusRaw = ArticleStatus.processing.rawValue
            return a
        }())
    }
}
