import SwiftUI
import NukeUI

struct SearchResultRow: View {
    let item: SearchViewModel.SearchResultItem
    let searchQuery: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            // Thumbnail
            if let coverURL = item.article.coverImageURL, let url = URL(string: coverURL) {
                LazyImage(url: url) { state in
                    if let image = state.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Color.folio.separator
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
            }

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                // Title with highlighted keywords
                highlightedTitleView
                    .font(Typography.listTitle)
                    .lineLimit(2)

                // Snippet
                if let snippet = item.snippet {
                    highlightedTextView(snippet)
                        .font(Typography.body)
                        .foregroundStyle(Color.folio.textSecondary)
                        .lineLimit(2)
                } else if let summary = item.article.summary {
                    Text(summary)
                        .font(Typography.body)
                        .foregroundStyle(Color.folio.textSecondary)
                        .lineLimit(2)
                }

                // Meta info
                HStack(spacing: Spacing.xxs) {
                    sourceIcon
                    if let siteName = item.article.siteName {
                        Text(siteName)
                            .font(Typography.caption)
                            .foregroundStyle(Color.folio.textTertiary)
                    }
                    Text("\u{00B7}")
                        .foregroundStyle(Color.folio.textTertiary)
                    Text(item.article.createdAt.relativeFormatted())
                        .font(Typography.caption)
                        .foregroundStyle(Color.folio.textTertiary)
                }

                // Tags
                if !item.article.tags.isEmpty {
                    HStack(spacing: Spacing.xxs) {
                        ForEach(item.article.tags.prefix(3)) { tag in
                            TagChip(text: tag.name)
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

    // MARK: - Highlighted Title

    @ViewBuilder
    private var highlightedTitleView: some View {
        if let hlTitle = item.highlightedTitle {
            highlightedTextView(hlTitle)
                .foregroundStyle(Color.folio.textPrimary)
        } else {
            Text(item.article.title ?? item.article.url)
                .foregroundStyle(Color.folio.textPrimary)
        }
    }

    /// Parse `<mark>...</mark>` tags from FTS5 highlight output and render
    /// matching fragments with the highlight color.
    private func highlightedTextView(_ text: String) -> Text {
        let parts = text.components(separatedBy: "<mark>")
        var result = Text("")

        for (index, part) in parts.enumerated() {
            if index == 0 {
                result = result + Text(part)
            } else {
                let subparts = part.components(separatedBy: "</mark>")
                if subparts.count == 2 {
                    result = result
                        + Text(subparts[0])
                            .foregroundColor(Color.folio.accent)
                            .bold()
                        + Text(subparts[1])
                } else {
                    result = result + Text(part)
                }
            }
        }

        return result
    }

    // MARK: - Source Icon

    private var sourceIcon: some View {
        Group {
            switch item.article.sourceType {
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
