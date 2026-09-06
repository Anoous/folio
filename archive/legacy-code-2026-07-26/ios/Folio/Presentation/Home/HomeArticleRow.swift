import SwiftUI

enum ArticleRowAction {
    case loadMore
    case toggleFavorite
    case retry
    case delete
    case archive
    case share(URL)
    case copyLink(String)
}

struct HomeArticleRow: View {
    @Environment(\.selectArticle) private var selectArticle

    let article: Article
    let articleCount: Int
    let articleIndex: Int?
    let onAction: (ArticleRowAction) -> Void

    var body: some View {
        Button {
            if article.status == .failed {
                onAction(.retry)
            } else {
                selectArticle(article)
            }
        } label: {
            ArticleCardView(article: article)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityHint(article.status == .failed ? "重试处理" : "打开阅读")
        .onAppear {
            if let idx = articleIndex, idx >= articleCount - 5 {
                onAction(.loadMore)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                onAction(.delete)
            } label: {
                Label(String(localized: "reader.delete", defaultValue: "Delete"), systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                onAction(.toggleFavorite)
            } label: {
                Label(
                    article.isFavorite
                        ? String(localized: "reader.unfavorite", defaultValue: "Remove Favorite")
                        : String(localized: "reader.favorite", defaultValue: "Favorite"),
                    systemImage: article.isFavorite ? "heart.slash" : "heart"
                )
            }
            .tint(article.isFavorite ? .gray : .pink)
        }
        .contextMenu {
            contextMenuContent
        }
        .sensoryFeedback(.selection, trigger: article.isFavorite)
        .transition(.asymmetric(
            insertion: .identity,
            removal: .opacity.combined(with: .move(edge: .trailing))
        ))
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var contextMenuContent: some View {
        if article.status == .failed {
            Button {
                onAction(.retry)
            } label: {
                Label(String(localized: "article.retry", defaultValue: "Retry"), systemImage: "arrow.clockwise")
            }

            Divider()
        }

        Button {
            onAction(.toggleFavorite)
        } label: {
            Label(
                article.isFavorite
                    ? String(localized: "reader.unfavorite", defaultValue: "Remove Favorite")
                    : String(localized: "reader.favorite", defaultValue: "Favorite"),
                systemImage: article.isFavorite ? "heart.fill" : "heart"
            )
        }

        Button {
            onAction(.archive)
        } label: {
            Label(
                article.isArchived
                    ? String(localized: "reader.unarchive", defaultValue: "Unarchive")
                    : String(localized: "reader.archive", defaultValue: "Archive"),
                systemImage: article.isArchived ? "archivebox.fill" : "archivebox"
            )
        }

        if let urlString = article.url, let url = URL(string: urlString) {
            Button {
                onAction(.share(url))
            } label: {
                Label(String(localized: "reader.share", defaultValue: "Share"), systemImage: "square.and.arrow.up")
            }
        }

        if let urlString = article.url, !urlString.isEmpty {
            Button {
                onAction(.copyLink(urlString))
            } label: {
                Label(String(localized: "home.article.copyLink", defaultValue: "Copy Link"), systemImage: "link")
            }
        }

        Divider()

        Button(role: .destructive) {
            onAction(.delete)
        } label: {
            Label(String(localized: "reader.delete", defaultValue: "Delete"), systemImage: "trash")
        }
    }
}
