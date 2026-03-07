import Foundation
import SwiftData

extension Article {
    /// Mark this article as read with minimal progress.
    func markAsRead(in context: ModelContext) {
        if readProgress == 0 { readProgress = 0.01 }
        lastReadAt = Date()
        updatedAt = Date()
        try? context.save()
    }

    /// Toggle favorite with optimistic update and server sync.
    @MainActor
    func toggleFavoriteWithSync(
        context: ModelContext,
        apiClient: APIClient,
        isAuthenticated: Bool,
        showToast: @escaping (String, String?) -> Void
    ) {
        isFavorite.toggle()
        updatedAt = Date()
        try? context.save()

        showToast(
            isFavorite
                ? String(localized: "home.article.favorited", defaultValue: "Added to favorites")
                : String(localized: "home.article.unfavorited", defaultValue: "Removed from favorites"),
            isFavorite ? "heart.fill" : "heart"
        )

        guard isAuthenticated, let serverID else { return }
        Task {
            do {
                try await apiClient.updateArticle(
                    id: serverID,
                    request: UpdateArticleRequest(isFavorite: isFavorite)
                )
                syncState = .synced
            } catch {
                // Keep the user's intended value; mark for retry on next sync
                syncState = .pendingUpdate
                try? context.save()
                showToast(
                    String(localized: "home.article.syncFailed", defaultValue: "Sync failed, will retry"),
                    "exclamationmark.icloud"
                )
            }
        }
    }

    /// Toggle archive with optimistic update and server sync.
    @MainActor
    func toggleArchiveWithSync(
        context: ModelContext,
        apiClient: APIClient,
        isAuthenticated: Bool,
        showToast: @escaping (String, String?) -> Void
    ) {
        isArchived.toggle()
        updatedAt = Date()
        try? context.save()

        showToast(
            isArchived
                ? String(localized: "home.article.archived", defaultValue: "Archived")
                : String(localized: "home.article.unarchived", defaultValue: "Unarchived"),
            isArchived ? "archivebox.fill" : "archivebox"
        )

        guard isAuthenticated, let serverID else { return }
        Task {
            do {
                try await apiClient.updateArticle(
                    id: serverID,
                    request: UpdateArticleRequest(isArchived: isArchived)
                )
                syncState = .synced
            } catch {
                // Keep the user's intended value; mark for retry on next sync
                syncState = .pendingUpdate
                try? context.save()
                showToast(
                    String(localized: "home.article.syncFailed", defaultValue: "Sync failed, will retry"),
                    "exclamationmark.icloud"
                )
            }
        }
    }
}
