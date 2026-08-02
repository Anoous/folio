import SwiftUI

struct LibraryArticleRow: View {
    let article: DemoArticle
    let transitionNamespace: Namespace.ID
    let onOpen: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 9) {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(article.title)
                            .font(FolioTypography.editorial(19, relativeTo: .headline))
                            .foregroundStyle(.primary)

                        LibraryStatusAccessory(status: article.status)
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(article.title)
                            .font(FolioTypography.editorial(19, relativeTo: .headline))
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        Spacer(minLength: 8)

                        LibraryStatusAccessory(status: article.status)
                    }
                }

                HStack(spacing: 8) {
                    FolioBrandIcon(monogram: article.monogram, size: 26)

                    Text("\(article.source) · \(article.age)")
                        .font(.subheadline)
                        .foregroundStyle(FolioPalette.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                LibrarySummaryLine(article: article)
            }
            .padding(.vertical, 14)
            .contentShape(.rect)
        }
        .buttonStyle(FolioPressButtonStyle())
        .overlay(alignment: .bottomTrailing) {
            Rectangle()
                .fill(FolioPalette.paperLine.opacity(0.72))
                .frame(height: 0.6)
        }
        .matchedTransitionSource(id: article.id, in: transitionNamespace)
        .accessibilityHint("打开文章原文")
    }
}
