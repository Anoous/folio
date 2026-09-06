import SwiftUI
import NukeUI

struct LargeArticleCardView: View {
    let article: Article

    @Environment(\.heroNamespace) private var heroNamespace

    private var isUnread: Bool {
        article.readProgress == 0 && article.status == .ready
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Cover image
            if let coverURL = article.coverImageURL, let url = URL(string: coverURL) {
                LazyImage(url: url) { state in
                    if let image = state.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(maxWidth: .infinity, maxHeight: 180)
                            .clipped()
                    } else {
                        Rectangle()
                            .fill(Color.folio.separator.opacity(0.2))
                            .frame(height: 180)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: 180)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.bottom, 14)
            }

            // Title
            Text(article.displayTitle)
                .font(isUnread ? Typography.v3CardTitleUnread : Typography.v3CardTitle)
                .foregroundStyle(FolioPaperPalette.primaryText)
                .lineSpacing(17 * 0.45)
                .lineLimit(2)
                .modifier(HeroGeometryModifier(id: "title-\(article.id)", namespace: heroNamespace))

            // Summary
            if let summary = article.displaySummary, !summary.isEmpty {
                HStack(alignment: .top, spacing: 0) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(isUnread ? FolioPaperPalette.accentBlue : FolioPaperPalette.quaternaryText)
                        .frame(width: 2)
                    Text(summary)
                        .font(Typography.v3CardInsight)
                        .foregroundStyle(isUnread ? FolioPaperPalette.secondaryText : FolioPaperPalette.tertiaryText)
                        .lineLimit(2)
                        .padding(.leading, 14)
                }
                .padding(.top, Spacing.xs)
            }

            // Meta line
            metaLine
                .padding(.top, Spacing.sm)
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
                .foregroundStyle(FolioPaperPalette.quaternaryText)
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
