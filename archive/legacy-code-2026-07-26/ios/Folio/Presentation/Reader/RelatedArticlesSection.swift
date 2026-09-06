import SwiftUI

// MARK: - Related Article (local mock struct)

private struct RelatedArticleItem: Identifiable {
    let id = UUID()
    let title: String
    let siteName: String
}

// MARK: - RelatedArticlesSection

struct RelatedArticlesSection: View {
    private let items: [RelatedArticleItem] = [
        RelatedArticleItem(
            title: "Understanding Swift Concurrency in Practice",
            siteName: "Swift Blog"
        ),
        RelatedArticleItem(
            title: "Building Offline-First Apps with SwiftData",
            siteName: "WWDC Notes"
        ),
        RelatedArticleItem(
            title: "Modern iOS Architecture Patterns",
            siteName: "objc.io"
        ),
    ]

    private let cardWidth: CGFloat = 160

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Section header
            HStack(spacing: Spacing.xxs) {
                Image(systemName: "link")
                    .font(.caption)
                    .foregroundStyle(Color.folio.textTertiary)
                Text(String(localized: "reader.relatedArticles", defaultValue: "Related in your collection"))
                    .font(Typography.tag)
                    .foregroundStyle(Color.folio.textSecondary)
            }

            // Horizontal scroll of cards
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(items) { item in
                        relatedCard(item)
                    }
                }
            }
        }
    }

    private func relatedCard(_ item: RelatedArticleItem) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(item.title)
                .font(Typography.caption)
                .foregroundStyle(Color.folio.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(item.siteName)
                .font(.caption2)
                .foregroundStyle(Color.folio.textTertiary)
                .lineLimit(1)
        }
        .frame(width: cardWidth, alignment: .topLeading)
        .padding(Spacing.sm)
        .background(Color.folio.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
    }
}

#Preview {
    RelatedArticlesSection()
        .padding()
}
