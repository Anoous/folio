import Foundation
import SwiftData

@MainActor
final class ArticleActionWorkflow {
    private let apiClient: APIClient
    private let context: ModelContext
    private let searchIndexCoordinator: SearchIndexCoordinator

    init(
        apiClient: APIClient = .shared,
        context: ModelContext,
        searchIndexCoordinator: SearchIndexCoordinator? = nil
    ) {
        self.apiClient = apiClient
        self.context = context
        self.searchIndexCoordinator = searchIndexCoordinator ?? .shared
    }

    func markAsRead(_ article: Article) {
        article.markAsRead(in: context)
    }

    func toggleFavorite(
        _ article: Article,
        isAuthenticated: Bool,
        showToast: @escaping (String, String?) -> Void
    ) {
        toggleBool(
            article,
            dirtyField: .favorite,
            toggle: { $0.isFavorite.toggle() },
            makeRequest: {
                UpdateArticleRequest(
                    isFavorite: $0.isFavorite,
                    favoriteUpdatedAt: $0.favoriteUpdatedAt
                )
            },
            toastOn: (
                String(localized: "home.article.favorited", defaultValue: "Added to favorites"),
                "heart.fill"
            ),
            toastOff: (
                String(localized: "home.article.unfavorited", defaultValue: "Removed from favorites"),
                "heart"
            ),
            getValue: { $0.isFavorite },
            isAuthenticated: isAuthenticated,
            showToast: showToast
        )
    }

    func toggleArchive(
        _ article: Article,
        isAuthenticated: Bool,
        showToast: @escaping (String, String?) -> Void
    ) {
        toggleBool(
            article,
            dirtyField: .archived,
            toggle: { $0.isArchived.toggle() },
            makeRequest: {
                UpdateArticleRequest(
                    isArchived: $0.isArchived,
                    archivedUpdatedAt: $0.archivedUpdatedAt
                )
            },
            toastOn: (
                String(localized: "home.article.archived", defaultValue: "Archived"),
                "archivebox.fill"
            ),
            toastOff: (
                String(localized: "home.article.unarchived", defaultValue: "Unarchived"),
                "archivebox"
            ),
            getValue: { $0.isArchived },
            isAuthenticated: isAuthenticated,
            showToast: showToast
        )
    }

    func delete(_ article: Article) {
        article.cleanupLocalImage()
        searchIndexCoordinator.remove(articleID: article.id)

        if let serverID = article.serverID {
            context.insert(PendingDeletion(serverID: serverID))
            let existing = try? context.fetch(FetchDescriptor<DeletionRecord>(
                predicate: #Predicate<DeletionRecord> { $0.serverID == serverID }
            ))
            if existing?.isEmpty ?? true {
                context.insert(DeletionRecord(serverID: serverID))
            }
        }

        context.delete(article)
        ModelContext.safeSave(context)
    }

    private func toggleBool(
        _ article: Article,
        dirtyField: ArticleDirtyField,
        toggle: (Article) -> Void,
        makeRequest: @escaping (Article) -> UpdateArticleRequest,
        toastOn: (String, String),
        toastOff: (String, String),
        getValue: @escaping (Article) -> Bool,
        isAuthenticated: Bool,
        showToast: @escaping (String, String?) -> Void
    ) {
        toggle(article)
        article.markPendingUpdateIfNeeded(for: dirtyField)
        ModelContext.safeSave(context)

        let value = getValue(article)
        let toast = value ? toastOn : toastOff
        showToast(toast.0, toast.1)

        guard isAuthenticated, let serverID = article.serverID else { return }
        Task { @MainActor in
            do {
                try await apiClient.updateArticle(id: serverID, request: makeRequest(article))
                if getValue(article) == value {
                    article.clearPendingUpdateIfNeeded(for: dirtyField)
                } else {
                    article.markPendingUpdateIfNeeded(for: dirtyField)
                }
                ModelContext.safeSave(context)
            } catch {
                article.markPendingUpdateIfNeeded(for: dirtyField)
                ModelContext.safeSave(context)
                showToast(
                    String(localized: "home.article.syncFailed", defaultValue: "Sync failed, will retry"),
                    "exclamationmark.icloud"
                )
            }
        }
    }
}
