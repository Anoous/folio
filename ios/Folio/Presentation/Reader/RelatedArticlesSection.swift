import SwiftUI

struct RelatedArticlesSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xxs) {
                Image(systemName: "link")
                    .font(.caption)
                    .foregroundStyle(Color.folio.accent)
                Text(String(localized: "related.title", defaultValue: "Related in your collection"))
                    .font(Typography.tag)
                    .foregroundStyle(Color.folio.textSecondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(MockRelatedArticle.samples) { item in
                        relatedCard(item)
                    }
                }
            }
        }
        .padding(.top, Spacing.lg)
    }

    private func relatedCard(_ item: MockRelatedArticle) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(item.title)
                .font(Typography.body)
                .foregroundStyle(Color.folio.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(item.source)
                .font(Typography.caption)
                .foregroundStyle(Color.folio.textTertiary)

            HStack(spacing: Spacing.xxs) {
                Image(systemName: "sparkle")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.folio.accent)
                Text(item.reason)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.folio.accent)
            }
        }
        .padding(Spacing.sm)
        .frame(width: 200, alignment: .leading)
        .background(Color.folio.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
    }
}

// MARK: - Mock Data

private struct MockRelatedArticle: Identifiable {
    let id = UUID()
    let title: String
    let source: String
    let reason: String

    static let samples: [MockRelatedArticle] = [
        MockRelatedArticle(
            title: "RAG Best Practices for Production",
            source: "blog.langchain.dev",
            reason: String(localized: "related.reason.topic", defaultValue: "Same topic")
        ),
        MockRelatedArticle(
            title: "Vector Database Comparison 2026",
            source: "thenewstack.io",
            reason: String(localized: "related.reason.complement", defaultValue: "Complements this")
        ),
        MockRelatedArticle(
            title: "Building Search with Embeddings",
            source: "simonwillison.net",
            reason: String(localized: "related.reason.deepDive", defaultValue: "Goes deeper")
        ),
    ]
}

#Preview {
    RelatedArticlesSection()
        .padding()
}
