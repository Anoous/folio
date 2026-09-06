import Foundation
import SwiftData

@MainActor
final class ArticleUpdateSyncWorkflow {
    private let apiClient: APIClient
    private let context: ModelContext

    init(apiClient: APIClient, context: ModelContext) {
        self.apiClient = apiClient
        self.context = context
    }

    func syncPendingUpdates() async {
        let pendingUpdateRaw = SyncState.pendingUpdate.rawValue
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { $0.syncStateRaw == pendingUpdateRaw }
        )
        guard let articles = try? context.fetch(descriptor), !articles.isEmpty else { return }

        await syncPendingUpdates(articles)
    }

    func syncPendingUpdates(_ articles: [Article]) async {
        FolioLogger.sync.info("syncing \(articles.count) pending update(s)")
        for article in articles {
            await syncPendingUpdate(article)
        }
        try? context.save()
    }

    private func syncPendingUpdate(_ article: Article) async {
        guard let serverID = article.serverID else { return }
        let dirtyFields = article.pendingDirtyFields
        guard !dirtyFields.isEmpty else {
            article.syncState = .synced
            return
        }

        let request = makeUpdateRequest(for: article, dirtyFields: dirtyFields)

        do {
            try await apiClient.updateArticle(id: serverID, request: request)
            clearSyncedFields(on: article, sent: request)
        } catch let error as APIError where error == .notFound {
            FolioLogger.sync.info("article deleted on server, accepting: \(serverID)")
            article.syncState = .synced
            article.dirtyFields = []
        } catch {
            FolioLogger.sync.error("update sync failed: \(serverID) — \(error)")
        }
    }

    private func makeUpdateRequest(for article: Article, dirtyFields: Set<ArticleDirtyField>) -> UpdateArticleRequest {
        var request = UpdateArticleRequest()
        if dirtyFields.contains(.favorite) {
            request.isFavorite = article.isFavorite
            request.favoriteUpdatedAt = article.effectiveFieldUpdatedAt(for: .favorite)
        }
        if dirtyFields.contains(.archived) {
            request.isArchived = article.isArchived
            request.archivedUpdatedAt = article.effectiveFieldUpdatedAt(for: .archived)
        }
        if dirtyFields.contains(.readProgress) {
            request.readProgress = article.readProgress
            request.readProgressUpdatedAt = article.effectiveFieldUpdatedAt(for: .readProgress)
        }
        return request
    }

    private func clearSyncedFields(on article: Article, sent request: UpdateArticleRequest) {
        if let sentFavorite = request.isFavorite, article.isFavorite == sentFavorite {
            article.clearPendingUpdateIfNeeded(for: .favorite)
        }
        if let sentArchived = request.isArchived, article.isArchived == sentArchived {
            article.clearPendingUpdateIfNeeded(for: .archived)
        }
        if let sentReadProgress = request.readProgress, article.readProgress <= sentReadProgress {
            article.clearPendingUpdateIfNeeded(for: .readProgress)
        }
    }
}
