import SwiftUI

struct HomeArticlePreviewRow: View {
    let article: Article
    let subtitle: String
    let showsProgress: Bool

    @Environment(\.selectArticle) private var selectArticle

    var body: some View {
        Button {
            selectArticle(article)
        } label: {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                    Text(article.displayTitle)
                        .font(Typography.v3CardTitle)
                        .foregroundStyle(Color.folio.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: Spacing.sm)

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Color.folio.textTertiary)
                }

                Text(subtitle)
                    .font(Typography.caption)
                    .foregroundStyle(Color.folio.textTertiary)
                    .lineLimit(1)

                if showsProgress {
                    ProgressView(value: max(article.readProgress, 0.01))
                        .progressViewStyle(.linear)
                        .tint(Color.folio.accent)
                        .accessibilityLabel("阅读进度")
                        .accessibilityValue("\(Int(article.readProgress * 100))%")
                }
            }
            .padding(Spacing.md)
            .background(Color.folio.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
