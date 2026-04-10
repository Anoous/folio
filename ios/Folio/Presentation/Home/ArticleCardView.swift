import SwiftUI
import NukeUI

/// Dispatches to LargeArticleCardView / StandardArticleCardContent / CompactArticleCardView
/// based on `article.cardTier`, and wraps every tier with unified status indicators.
struct ArticleCardView: View {
    let article: Article

    var body: some View {
        if article.status == .pending && article.title == nil && article.markdownContent == nil && article.sourceType != .manual {
            ShimmerView()
        } else {
            ArticleStatusWrapper(article: article) {
                switch article.cardTier {
                case .large:
                    LargeArticleCardView(article: article)
                case .standard:
                    StandardArticleCardContent(article: article)
                case .compact:
                    CompactArticleCardView(article: article)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityDescription)
        }
    }

    private var accessibilityDescription: String {
        var parts = [article.displayTitle]
        if let summary = article.displaySummary { parts.append(summary) }
        if article.readProgress == 0 && article.status == .ready {
            parts.append(String(localized: "status.unread", defaultValue: "Unread"))
        }
        if article.isFavorite { parts.append(String(localized: "status.favorited", defaultValue: "Favorited")) }
        return parts.joined(separator: ". ")
    }
}

// MARK: - Unified Status Wrapper

/// Wraps any card tier with consistent status indicators:
/// - pending: 60% opacity, non-interactive feel
/// - processing: left accent bar with breathing animation + "正在分析..." label
/// - failed: bottom red bar
/// - clientReady: subtle "本地内容" label in meta
struct ArticleStatusWrapper<Content: View>: View {
    let article: Article
    @ViewBuilder let content: Content

    @State private var breathe = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left status bar
            if article.status == .processing {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.folio.accent)
                    .frame(width: 3)
                    .opacity(breathe ? 0.4 : 1.0)
                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: breathe)
                    .onAppear { breathe = true }
                    .padding(.trailing, 10)
            }

            VStack(alignment: .leading, spacing: 0) {
                content

                // Status label
                if article.status == .processing {
                    Text(String(localized: "status.analyzing", defaultValue: "Analyzing..."))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.folio.accent.opacity(0.8))
                        .padding(.top, 2)
                } else if article.status == .clientReady {
                    Text(String(localized: "status.localContent", defaultValue: "Local content"))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.folio.success.opacity(0.7))
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .opacity(article.status == .pending ? 0.6 : 1.0)
        .overlay(alignment: .bottom) {
            if article.status == .failed {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                    Text(String(localized: "status.failed.tapRetry", defaultValue: "Failed — tap to retry"))
                        .font(.system(size: 11))
                }
                .foregroundStyle(Color.folio.error.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
        }
    }
}

// MARK: - Standard Card (the original layout, extracted)

struct StandardArticleCardContent: View {
    @Environment(\.heroNamespace) private var heroNamespace

    let article: Article

    private var isUnread: Bool {
        article.readProgress == 0 && article.status == .ready
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    if article.sourceType == .voice {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.folio.textTertiary)
                    }
                    Text(article.displayTitle)
                        .font(isUnread ? Typography.v3CardTitleUnread : Typography.v3CardTitle)
                        .foregroundStyle(article.status == .failed ? Color.folio.textTertiary : Color.folio.textPrimary)
                        .lineSpacing(17 * 0.45)
                        .lineLimit(2)
                        .modifier(HeroGeometryModifier(id: "title-\(article.id)", namespace: heroNamespace))
                }

                if let summary = article.displaySummary, !summary.isEmpty {
                    HStack(alignment: .top, spacing: 0) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(isUnread ? Color.folio.accent : Color.folio.textQuaternary)
                            .frame(width: 2)
                        Text(summary)
                            .font(Typography.v3CardInsight)
                            .foregroundStyle(isUnread ? Color.folio.textSecondary : Color.folio.textTertiary)
                            .lineLimit(2)
                            .padding(.leading, 14)
                    }
                    .padding(.top, Spacing.xs)
                }

                metaLine
                    .padding(.top, Spacing.sm)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Thumbnail
            if let localPath = article.localImagePath,
               article.sourceType == .screenshot,
               let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConstants.appGroupIdentifier) {
                let imageURL = containerURL.appendingPathComponent(localPath)
                if let uiImage = UIImage(contentsOfFile: imageURL.path) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            } else if let coverURL = article.coverImageURL,
                      let url = URL(string: coverURL) {
                LazyImage(url: url) { state in
                    if let image = state.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .frame(width: 72, height: 72)
            }
        }
        .padding(.vertical, Spacing.md)
        .overlay(alignment: .topTrailing) {
            if article.isFavorite {
                Text("★")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.folio.warning.opacity(0.6))
                    .padding(.top, Spacing.md)
            }
        }
    }

    private var metaLine: some View {
        HStack(spacing: 0) {
            Text(metaLineText)
                .font(.system(size: 12))
                .foregroundStyle(Color.folio.textQuaternary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private var metaLineText: String {
        var parts: [String] = []
        if let sourceName = article.effectiveSourceName {
            parts.append(sourceName)
        }
        parts.append(article.createdAt.relativeFormatted())
        let tagNames = article.tags.prefix(2).map(\.name)
        parts.append(contentsOf: tagNames)
        return parts.joined(separator: " \u{00B7} ")
    }
}

// MARK: - Font line-height helper

private extension Font {
    func lineSpacingFor(lineHeight: CGFloat, size: CGFloat) -> CGFloat {
        (lineHeight - 1.0) * size
    }
}

#Preview("Card Tiers") {
    List {
        ArticleCardView(article: {
            let a = Article(url: "https://example.com", title: "The Future of Local-First Software Architecture", sourceType: .web)
            a.siteName = "martinfowler.com"
            a.coverImageURL = "https://picsum.photos/600/300"
            a.summary = "A comprehensive guide to local-first architecture, exploring how offline-capable apps can deliver better user experiences."
            a.wordCount = 2000
            a.statusRaw = ArticleStatus.ready.rawValue
            return a
        }())
        ArticleCardView(article: {
            let a = Article(url: "https://mp.weixin.qq.com/s/abc", title: "深入理解 Swift 并发模型", sourceType: .wechat)
            a.siteName = "SwiftGG"
            a.summary = "从 Actor 隔离到结构化并发，全面解析 Swift 5.9 的并发编程范式。"
            a.statusRaw = ArticleStatus.ready.rawValue
            return a
        }())
        ArticleCardView(article: {
            let a = Article(url: "https://x.com/user/status/123", title: "Claude Code is amazing", sourceType: .twitter)
            a.siteName = "Yanhua on X"
            a.statusRaw = ArticleStatus.ready.rawValue
            return a
        }())
        ArticleCardView(article: {
            let a = Article(url: "https://example.com/proc", title: "Processing article", sourceType: .web)
            a.statusRaw = ArticleStatus.processing.rawValue
            return a
        }())
        ArticleCardView(article: {
            let a = Article(url: "https://example.com/failed", title: "Failed article", sourceType: .web)
            a.statusRaw = ArticleStatus.failed.rawValue
            return a
        }())
    }
    .listStyle(.plain)
    .listRowSeparator(.hidden)
}
