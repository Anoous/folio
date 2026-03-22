import SwiftUI
import NukeUI

struct ArticleCardView: View {
    let article: Article

    private var isUnread: Bool {
        article.readProgress == 0 && article.status == .ready
    }

    private var isFailed: Bool {
        article.status == .failed
    }

    var body: some View {
        if article.status == .pending && article.title == nil && article.markdownContent == nil && article.sourceType != .manual {
            ShimmerView()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                // Title — serif font, weight signals unread
                Text(article.displayTitle)
                    .font(isUnread ? Typography.cardTitleUnread : Typography.cardTitle)
                    .foregroundStyle(isFailed ? Color.folio.textTertiary : (isUnread ? Color.folio.textPrimary : Color.folio.textSecondary))
                    .lineLimit(3)

                // Summary
                if let summary = article.displaySummary {
                    Text(summary)
                        .font(Typography.cardSummary)
                        .foregroundStyle(Color.folio.textTertiary)
                        .lineLimit(2)
                        .padding(.top, Spacing.xs)
                }

                // Source + time — minimal
                metaLine
                    .padding(.top, Spacing.sm)

                // Processing progress
                if article.status == .processing {
                    ProcessingProgressBar()
                        .padding(.top, Spacing.xs)
                } else if article.status == .clientReady {
                    ProcessingProgressBar(color: Color.folio.success.opacity(0.3))
                        .padding(.top, Spacing.xs)
                }
            }
            .padding(.vertical, Spacing.md)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityDescription)
        }
    }

    // MARK: - Meta Line (source + time only)

    private var metaLine: some View {
        HStack(spacing: 0) {
            // Source name
            if let sourceName = effectiveSourceName {
                Text(sourceName)
                    .font(Typography.cardMeta)
                    .foregroundStyle(Color.folio.textTertiary)

                Text(" \u{00B7} ")
                    .font(Typography.cardMeta)
                    .foregroundStyle(Color.folio.textTertiary)
            }

            // Time
            Text(article.createdAt.relativeFormatted())
                .font(Typography.cardMeta)
                .foregroundStyle(Color.folio.textTertiary)

            Spacer(minLength: 0)

            // Favorite — subtle
            if article.isFavorite {
                Image(systemName: "heart.fill")
                    .font(.caption2)
                    .foregroundStyle(.pink.opacity(0.7))
                    .accessibilityLabel(Text(String(localized: "status.favorited", defaultValue: "Favorited")))
            }

            // Failed — only status that still shows
            if isFailed {
                Image(systemName: "exclamationmark.circle")
                    .font(.caption2)
                    .foregroundStyle(Color.folio.error.opacity(0.6))
                    .accessibilityLabel(Text(String(localized: "status.failed", defaultValue: "Failed")))
            }
        }
    }

    // MARK: - Helpers

    private var effectiveSourceName: String? {
        if article.sourceType == .manual {
            return article.wordCount < 200
                ? String(localized: "source.thought", defaultValue: "My Thought")
                : String(localized: "source.pasted", defaultValue: "Pasted Content")
        }
        if let siteName = article.siteName, !siteName.isEmpty {
            return siteName
        }
        return nil
    }

    private var accessibilityDescription: String {
        var parts = [article.displayTitle]
        if let summary = article.displaySummary { parts.append(summary) }
        if isUnread { parts.append(String(localized: "status.unread", defaultValue: "Unread")) }
        if article.isFavorite { parts.append(String(localized: "status.favorited", defaultValue: "Favorited")) }
        return parts.joined(separator: ". ")
    }
}

#Preview("Editorial") {
    List {
        ArticleCardView(article: {
            let a = Article(url: "https://example.com", title: "The Future of Local-First Software Architecture", sourceType: .web)
            a.siteName = "martinfowler.com"
            a.summary = "A comprehensive guide to local-first architecture, exploring how offline-capable apps can deliver better user experiences while maintaining data consistency."
            a.statusRaw = ArticleStatus.ready.rawValue
            return a
        }())
        ArticleCardView(article: {
            let a = Article(url: "https://mp.weixin.qq.com/s/abc", title: "深入理解 Swift 并发模型", sourceType: .wechat)
            a.siteName = "SwiftGG"
            a.summary = "从 Actor 隔离到结构化并发，全面解析 Swift 5.9 的并发编程范式。"
            a.statusRaw = ArticleStatus.ready.rawValue
            a.readProgress = 0.3
            return a
        }())
        ArticleCardView(article: {
            let a = Article(url: "https://x.com/user/status/123", title: "Claude Code is amazing", sourceType: .twitter)
            a.siteName = "Yanhua on X"
            a.statusRaw = ArticleStatus.ready.rawValue
            a.isFavorite = true
            return a
        }())
    }
    .listStyle(.plain)
    .listRowSeparator(.hidden)
}
