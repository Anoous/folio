import SwiftUI

struct ArticleDetailHeader: View {
    let article: DemoArticle
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FolioBackButton(action: onBack)
                .padding(.leading, -14)
                .padding(.top, 13)

            HStack(spacing: 18) {
                FolioBrandIcon(monogram: article.monogram, size: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text(article.title)
                        .font(FolioTypography.editorial(22, relativeTo: .title2))
                        .lineLimit(2)

                    Text("\(article.source) · \(article.age)")
                        .font(.subheadline)
                        .foregroundStyle(FolioPalette.tertiaryText)
                }
            }
            .padding(.top, 15)
        }
    }
}
