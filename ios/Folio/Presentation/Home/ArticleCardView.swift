import SwiftUI
import NukeUI

struct ArticleCardView: View {
    @Environment(\.heroNamespace) private var heroNamespace

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
            cardContent
        }
    }

    // MARK: - Card Content

    private var cardContent: some View {
        HStack(alignment: .top, spacing: 14) {
            // Left: text content
            VStack(alignment: .leading, spacing: 0) {
                // Title — v3 LXGW WenKai TC font, weight signals unread
                HStack(spacing: 4) {
                    if article.sourceType == .voice {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.folio.textTertiary)
                    }
                    Text(article.displayTitle)
                        .font(isUnread ? Typography.v3CardTitleUnread : Typography.v3CardTitle)
                        .foregroundStyle(isFailed ? Color.folio.textTertiary : Color.folio.textPrimary)
                        .lineSpacing((isUnread ? Typography.v3CardTitleUnread : Typography.v3CardTitle).lineSpacingFor(lineHeight: 1.45, size: 17))
                        .lineLimit(2)
                        .modifier(HeroGeometryModifier(id: "title-\(article.id)", namespace: heroNamespace))
                }

                // Insight pull quote
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

                // Metadata line
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
            .frame(maxWidth: .infinity, alignment: .leading)

            // Right: thumbnail (if available)
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
                    } else {
                        Color.folio.cardBackground
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Meta Line (source · time · tags)

    private var metaLine: some View {
        HStack(spacing: 0) {
            Text(metaLineText)
                .font(.system(size: 12))
                .foregroundStyle(Color.folio.textQuaternary)
                .lineLimit(1)

            Spacer(minLength: 0)

            // Failed indicator
            if isFailed {
                Image(systemName: "exclamationmark.circle")
                    .font(.caption2)
                    .foregroundStyle(Color.folio.error.opacity(0.6))
                    .accessibilityLabel(Text(String(localized: "status.failed", defaultValue: "Failed")))
            }
        }
    }

    private var metaLineText: String {
        var parts: [String] = []
        if let sourceName = effectiveSourceName {
            parts.append(sourceName)
        }
        parts.append(article.createdAt.relativeFormatted())
        let tagNames = article.tags.prefix(2).map(\.name)
        parts.append(contentsOf: tagNames)
        return parts.joined(separator: " \u{00B7} ")
    }

    // MARK: - Helpers

    private var effectiveSourceName: String? {
        switch article.sourceType {
        case .manual:
            return article.wordCount < 200
                ? String(localized: "source.thought", defaultValue: "My Thought")
                : String(localized: "source.pasted", defaultValue: "Pasted Content")
        case .screenshot:
            return String(localized: "Screenshot", defaultValue: "截图")
        case .voice:
            return String(localized: "Voice Note", defaultValue: "语音笔记")
        default:
            if let siteName = article.siteName, !siteName.isEmpty {
                return siteName
            }
            return nil
        }
    }

    private var accessibilityDescription: String {
        var parts = [article.displayTitle]
        if let summary = article.displaySummary { parts.append(summary) }
        if isUnread { parts.append(String(localized: "status.unread", defaultValue: "Unread")) }
        if article.isFavorite { parts.append(String(localized: "status.favorited", defaultValue: "Favorited")) }
        return parts.joined(separator: ". ")
    }
}

// MARK: - Font line-height helper

private extension Font {
    /// Returns SwiftUI `lineSpacing` to achieve the desired `lineHeight` multiplier.
    /// lineSpacing = (lineHeight * fontSize) - fontSize
    func lineSpacingFor(lineHeight: CGFloat, size: CGFloat) -> CGFloat {
        (lineHeight - 1.0) * size
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
            a.coverImageURL = "https://picsum.photos/200"
            a.statusRaw = ArticleStatus.ready.rawValue
            a.isFavorite = true
            return a
        }())
        ArticleCardView(article: {
            let a = Article(url: "https://example.com/pending", title: nil, sourceType: .web)
            a.statusRaw = ArticleStatus.pending.rawValue
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
    .listRowInsets(EdgeInsets())
}
