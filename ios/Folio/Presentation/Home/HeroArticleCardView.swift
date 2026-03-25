import SwiftUI

struct HeroArticleCardView: View {
    @Environment(\.heroNamespace) private var heroNamespace

    let article: Article

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 1. Title
            HStack(spacing: 6) {
                if article.sourceType == .voice {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.folio.textTertiary)
                }
                Text(article.displayTitle)
                    .font(Typography.v3HeroTitle)
                    .foregroundStyle(Color.folio.textPrimary)
                    .lineSpacing(24 * 0.4)
                    .tracking(-0.2)
                    .modifier(HeroGeometryModifier(id: "title-\(article.id)", namespace: heroNamespace))
            }
            .padding(.bottom, 14)

            // 2. Insight pull quote (if summary exists)
            if let summary = article.displaySummary, !summary.isEmpty {
                HStack(alignment: .top, spacing: 0) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.folio.accent)
                        .frame(width: 2)
                    Text(summary)
                        .font(Typography.v3HeroInsight)
                        .foregroundStyle(Color.folio.textSecondary)
                        .lineSpacing(16 * 0.65)
                        .padding(.leading, 14)
                }
                .padding(.bottom, 14)
            }

            // 3. Metadata row
            HStack(spacing: 6) {
                if let sourceName = article.effectiveSourceName {
                    Text(sourceName)
                    dotSeparator
                }
                Text(article.createdAt.relativeFormatted())
                if !article.tags.isEmpty {
                    dotSeparator
                    Text(article.tags.prefix(2).map(\.name).joined(separator: " · "))
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(Color.folio.textTertiary)
        }
        .padding(.bottom, 24)
    }

    private var dotSeparator: some View {
        Circle()
            .fill(Color.folio.textQuaternary)
            .frame(width: 2, height: 2)
    }
}
