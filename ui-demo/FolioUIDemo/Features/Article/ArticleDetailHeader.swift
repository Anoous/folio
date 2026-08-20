import SwiftUI

struct ArticleDetailHeader: View {
    let article: DemoArticle

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(height: 57)

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

struct ArticleDetailTopBar: View {
    let onBack: () -> Void
    let onOpenReaderAppearance: () -> Void
    let readerAppearanceDescription: String

    var body: some View {
        HStack {
            FolioBackButton(action: onBack)
                .padding(.leading, -14)

            Spacer()

            Button(action: onOpenReaderAppearance) {
                Text("Aa")
                    .font(.system(.headline, design: .serif, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(FolioPalette.inkGreenDeep)
            .background(FolioPalette.surface.opacity(0.82), in: .circle)
            .overlay {
                Circle()
                    .stroke(FolioPalette.paperLine.opacity(0.8), lineWidth: 1)
            }
            .accessibilityLabel("阅读外观")
            .accessibilityValue(readerAppearanceDescription)
        }
        .padding(.horizontal, FolioMetrics.readingInset)
        .padding(.top, 13)
    }
}
