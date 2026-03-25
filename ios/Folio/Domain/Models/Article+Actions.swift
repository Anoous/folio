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

    /// Generic optimistic toggle + server sync pattern.
    @MainActor
    private func toggleBoolWithSync(
        toggle: () -> Void,
        makeRequest: @escaping () -> UpdateArticleRequest,
        toastOn: (String, String),
        toastOff: (String, String),
        getValue: () -> Bool,
        context: ModelContext,
        apiClient: APIClient,
        isAuthenticated: Bool,
        showToast: @escaping (String, String?) -> Void
    ) {
        toggle()
        markPendingUpdateIfNeeded()
        ModelContext.safeSave(context)

        let value = getValue()
        let toast = value ? toastOn : toastOff
        showToast(toast.0, toast.1)

        guard isAuthenticated, let serverID else { return }
        Task {
            do {
                try await apiClient.updateArticle(id: serverID, request: makeRequest())
                syncState = .synced
                ModelContext.safeSave(context)
            } catch {
                syncState = .pendingUpdate
                ModelContext.safeSave(context)
                showToast(
                    String(localized: "home.article.syncFailed", defaultValue: "Sync failed, will retry"),
                    "exclamationmark.icloud"
                )
            }
        }
    }

    /// Toggle favorite with optimistic update and server sync.
    @MainActor
    func toggleFavoriteWithSync(
        context: ModelContext,
        apiClient: APIClient,
        isAuthenticated: Bool,
        showToast: @escaping (String, String?) -> Void
    ) {
        toggleBoolWithSync(
            toggle: { isFavorite.toggle() },
            makeRequest: { [self] in UpdateArticleRequest(isFavorite: isFavorite) },
            toastOn: (
                String(localized: "home.article.favorited", defaultValue: "Added to favorites"),
                "heart.fill"
            ),
            toastOff: (
                String(localized: "home.article.unfavorited", defaultValue: "Removed from favorites"),
                "heart"
            ),
            getValue: { isFavorite },
            context: context,
            apiClient: apiClient,
            isAuthenticated: isAuthenticated,
            showToast: showToast
        )
    }

    /// Toggle archive with optimistic update and server sync.
    @MainActor
    func toggleArchiveWithSync(
        context: ModelContext,
        apiClient: APIClient,
        isAuthenticated: Bool,
        showToast: @escaping (String, String?) -> Void
    ) {
        toggleBoolWithSync(
            toggle: { isArchived.toggle() },
            makeRequest: { [self] in UpdateArticleRequest(isArchived: isArchived) },
            toastOn: (
                String(localized: "home.article.archived", defaultValue: "Archived"),
                "archivebox.fill"
            ),
            toastOff: (
                String(localized: "home.article.unarchived", defaultValue: "Unarchived"),
                "archivebox"
            ),
            getValue: { isArchived },
            context: context,
            apiClient: apiClient,
            isAuthenticated: isAuthenticated,
            showToast: showToast
        )
    }
}
