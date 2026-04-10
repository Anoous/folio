import SwiftUI

struct CompactArticleCardView: View {
    let article: Article

    @Environment(\.heroNamespace) private var heroNamespace

    private var isUnread: Bool {
        article.readProgress == 0 && article.status == .ready
    }

    var body: some View {
        HStack(spacing: 10) {
            // Source type icon
            Image(systemName: article.sourceType.iconName)
                .font(.system(size: 13))
                .foregroundStyle(Color.folio.textQuaternary)
                .frame(width: 20)

            // Title (single line)
            Text(article.displayTitle)
                .font(isUnread ? Typography.v3CardTitleUnread : Typography.v3CardTitle)
                .foregroundStyle(Color.folio.textPrimary)
                .lineLimit(1)
                .modifier(HeroGeometryModifier(id: "title-\(article.id)", namespace: heroNamespace))

            Spacer(minLength: 0)

            // Favorite star
            if article.isFavorite {
                Text("★")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.folio.warning.opacity(0.6))
            }

            // Time
            Text(article.createdAt.relativeFormatted())
                .font(.system(size: 12))
                .foregroundStyle(Color.folio.textQuaternary)
        }
        .padding(.vertical, Spacing.sm)
    }
}
