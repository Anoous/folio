import Foundation
import SwiftData

extension Article {
    func markPendingUpdateIfNeeded(for field: ArticleDirtyField, at timestamp: Date = .now) {
        guard serverID != nil else { return }
        guard syncState != .pendingUpload else { return }

        var fields = dirtyFields
        fields.insert(field)
        dirtyFields = fields
        setFieldUpdatedAt(timestamp, for: field)
        syncState = .pendingUpdate
        updatedAt = timestamp
    }

    func clearPendingUpdateIfNeeded(for field: ArticleDirtyField) {
        var fields = dirtyFields
        fields.remove(field)
        dirtyFields = fields

        guard syncState != .pendingUpload else { return }
        syncState = fields.isEmpty ? .synced : .pendingUpdate
    }

    /// Marks this article as having local changes that still need server sync.
    func markAsRead(in context: ModelContext) {
        if readProgress == 0 { readProgress = 0.01 }
        lastReadAt = Date()
        markPendingUpdateIfNeeded(for: .readProgress)
        ModelContext.safeSave(context)
    }

    /// Prepare this article for deletion: clean up local image, record sync intent,
    /// and delete from SwiftData. Callers handle post-actions (refetch, toast, dismiss).
    @MainActor
    func prepareForDeletion(
        context: ModelContext,
        searchIndexCoordinator: SearchIndexCoordinator? = nil
    ) {
        let searchIndexCoordinator = searchIndexCoordinator ?? .shared
        cleanupLocalImage()
        searchIndexCoordinator.remove(articleID: id)

        if let serverID {
            context.insert(PendingDeletion(serverID: serverID))
            let existing = try? context.fetch(FetchDescriptor<DeletionRecord>(
                predicate: #Predicate<DeletionRecord> { $0.serverID == serverID }
            ))
            if existing?.isEmpty ?? true {
                context.insert(DeletionRecord(serverID: serverID))
            }
        }

        context.delete(self)
        ModelContext.safeSave(context)
    }

    /// Generic optimistic toggle + server sync pattern.
    @MainActor
    private func toggleBoolWithSync(
        dirtyField: ArticleDirtyField,
        toggle: () -> Void,
        makeRequest: @escaping () -> UpdateArticleRequest,
        toastOn: (String, String),
        toastOff: (String, String),
        getValue: @escaping () -> Bool,
        context: ModelContext,
        apiClient: APIClient,
        isAuthenticated: Bool,
        showToast: @escaping (String, String?) -> Void
    ) {
        toggle()
        markPendingUpdateIfNeeded(for: dirtyField)
        ModelContext.safeSave(context)

        let value = getValue()
        let toast = value ? toastOn : toastOff
        showToast(toast.0, toast.1)

        guard isAuthenticated, let serverID else { return }
        Task {
            do {
                try await apiClient.updateArticle(id: serverID, request: makeRequest())
                if getValue() == value {
                    clearPendingUpdateIfNeeded(for: dirtyField)
                } else {
                    markPendingUpdateIfNeeded(for: dirtyField)
                }
                ModelContext.safeSave(context)
            } catch {
                markPendingUpdateIfNeeded(for: dirtyField)
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
            dirtyField: .favorite,
            toggle: { isFavorite.toggle() },
            makeRequest: { [self] in
                UpdateArticleRequest(
                    isFavorite: isFavorite,
                    favoriteUpdatedAt: favoriteUpdatedAt
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
            getValue: { [self] in isFavorite },
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
            dirtyField: .archived,
            toggle: { isArchived.toggle() },
            makeRequest: { [self] in
                UpdateArticleRequest(
                    isArchived: isArchived,
                    archivedUpdatedAt: archivedUpdatedAt
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
            getValue: { [self] in isArchived },
            context: context,
            apiClient: apiClient,
            isAuthenticated: isAuthenticated,
            showToast: showToast
        )
    }
}
