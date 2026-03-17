import Foundation
import SwiftData

extension Article {
    /// Marks this article as having local changes that still need server sync.
    func markPendingUpdateIfNeeded() {
        guard serverID != nil else { return }
        guard syncState != .pendingUpload else { return }
        syncState = .pendingUpdate
        updatedAt = Date()
    }

    /// Mark this article as read with minimal progress.
    func markAsRead(in context: ModelContext) {
        if readProgress == 0 { readProgress = 0.01 }
        lastReadAt = Date()
        markPendingUpdateIfNeeded()
        ModelContext.safeSave(context)
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
        markPendingUpdateIfNeeded()
        ModelContext.safeSave(context)

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
                ModelContext.safeSave(context)
            } catch {
                // Keep the user's intended value; mark for retry on next sync
                syncState = .pendingUpdate
                ModelContext.safeSave(context)
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
        markPendingUpdateIfNeeded()
        ModelContext.safeSave(context)

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
                ModelContext.safeSave(context)
            } catch {
                // Keep the user's intended value; mark for retry on next sync
                syncState = .pendingUpdate
                ModelContext.safeSave(context)
                showToast(
                    String(localized: "home.article.syncFailed", defaultValue: "Sync failed, will retry"),
                    "exclamationmark.icloud"
                )
            }
        }
    }
}
