import SwiftUI

struct ReaderBottomToolbar: View {
    let article: Article
    let readingProgress: Double
    let readingTheme: ReadingTheme
    let onOpenOriginal: () -> Void
    let onToggleFavorite: () -> Void
    let onShare: () -> Void

    var body: some View {
        GeometryReader { proxy in
            HStack {
                Button(action: onOpenOriginal) {
                    Image(systemName: "globe")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.folio.textSecondary)
                        .frame(width: 40, height: 40)
                }
                .accessibilityLabel(String(localized: "reader.openOriginal", defaultValue: "Open Original"))
                .opacity(article.url != nil ? 1 : 0)
                .disabled(article.url == nil)

                Spacer()

                Button(action: onToggleFavorite) {
                    Image(systemName: article.isFavorite ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 18))
                        .foregroundStyle(article.isFavorite ? Color.folio.accent : Color.folio.textSecondary)
                        .frame(width: 40, height: 40)
                }
                .accessibilityLabel(
                    article.isFavorite
                        ? String(localized: "reader.unfavorite", defaultValue: "Remove Favorite")
                        : String(localized: "reader.favorite", defaultValue: "Favorite")
                )

                Spacer()

                Text("\(Int(readingProgress * 100))%")
                    .font(.system(size: 13, weight: .medium))
                    .tracking(0.5)
                    .foregroundStyle(Color.folio.textTertiary)
                    .accessibilityLabel(String(localized: "reader.progressLabel", defaultValue: "Reading progress \(Int(readingProgress * 100)) percent"))

                Spacer()

                Button(action: onShare) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.folio.textSecondary)
                        .frame(width: 40, height: 40)
                }
                .accessibilityLabel(String(localized: "reader.shareArticle", defaultValue: "Share article"))
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.top, 10)
            .padding(.bottom, max(proxy.safeAreaInsets.bottom, 12))
            .background(
                LinearGradient(
                    stops: [
                        .init(color: readingTheme.backgroundColor.opacity(0), location: 0),
                        .init(color: readingTheme.backgroundColor, location: 0.3),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .frame(height: 62)
    }
}
