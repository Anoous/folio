import Foundation
import os
import SwiftData

@MainActor
@Observable
final class SyncService {
    private let apiClient: APIClient
    private let context: ModelContext
    private let searchIndexCoordinator: SearchIndexCoordinator
    private let cursorStore: ArticleSyncCursorStore
    private var isSyncing = false
    private var pollingTasks: [UUID: Task<Void, Never>] = [:]

    private static let pollMaxAttempts = 10
    private static let pollInterval: Duration = .seconds(5)

    init(
        apiClient: APIClient = .shared,
        context: ModelContext,
        searchIndexCoordinator: SearchIndexCoordinator? = nil,
        cursorStore: ArticleSyncCursorStore = ArticleSyncCursorStore()
    ) {
        self.apiClient = apiClient
        self.context = context
        self.searchIndexCoordinator = searchIndexCoordinator ?? .shared
        self.cursorStore = cursorStore
    }

    // MARK: - Article Submit

    /// Submit pending articles to the server. Returns a map of article UUID → success.
    func submitPendingArticles(_ articles: [Article]) async -> [UUID: Bool] {
        let workflow = ArticleSyncWorkflow(apiClient: apiClient, context: context)
        return await workflow.submitPendingArticles(articles) { [weak self] localID, taskID in
            guard let self else { return }
            let pollingTask = Task {
                await self.pollTask(taskId: taskID, articleLocalId: localID)
            }
            self.pollingTasks[localID] = pollingTask
        }
    }

    // MARK: - Submit Local Pending Articles

    /// Fetch and submit articles that are pending upload to the server.
    private func submitLocalPendingArticles() async {
        let pendingRaw = ArticleStatus.pending.rawValue
        let clientReadyRaw = ArticleStatus.clientReady.rawValue
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { $0.statusRaw == pendingRaw || $0.statusRaw == clientReadyRaw },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        guard let pending = try? context.fetch(descriptor), !pending.isEmpty else { return }

        // Clear stale serverIDs (article was 404'd but not deleted by merger,
        // meaning it should be re-uploaded as a new article).
        for article in pending {
            if article.serverID != nil {
                article.serverID = nil
            }
        }

        FolioLogger.sync.info("submitting \(pending.count) local pending article(s)")
        _ = await submitPendingArticles(pending)
    }

    // MARK: - Task Polling

    private func pollTask(taskId: String, articleLocalId: UUID) async {
        defer {
            pollingTasks.removeValue(forKey: articleLocalId)
        }

        for _ in 0..<Self.pollMaxAttempts {
            do {
                try await Task.sleep(for: Self.pollInterval)
            } catch is CancellationError {
                FolioLogger.sync.debug("task polling cancelled during sleep: \(taskId)")
                return
            } catch {
                FolioLogger.sync.debug("task polling sleep failed: \(error) — task \(taskId)")
                return
            }

            guard !Task.isCancelled else {
                FolioLogger.sync.debug("task polling cancelled before request: \(taskId)")
                return
            }

            do {
                let task = try await apiClient.getTask(id: taskId)

                switch task.status {
                case AppConstants.TaskStatus.done:
                    FolioLogger.sync.info("task done: \(taskId)")
                    if let articleId = task.articleId {
                        await fetchAndUpdateArticle(serverID: articleId, localID: articleLocalId)
                    }
                    return
                case AppConstants.TaskStatus.failed:
                    FolioLogger.sync.error("task failed: \(taskId) — \(task.errorMessage ?? "unknown")")
                    updateArticleStatus(localID: articleLocalId, status: .failed, error: task.errorMessage)
                    return
                case AppConstants.TaskStatus.queued,
                     AppConstants.TaskStatus.crawling,
                     AppConstants.TaskStatus.aiProcessing:
                    continue
                default:
                    continue
                }
            } catch {
                guard !Task.isCancelled else {
                    FolioLogger.sync.debug("task polling cancelled after request: \(taskId)")
                    return
                }
                FolioLogger.sync.debug("poll network error: \(error) — task \(taskId)")
                continue
            }
        }

        FolioLogger.sync.error("task polling timed out: \(taskId)")
        updateArticleStatus(localID: articleLocalId, status: .failed, error: "Processing timed out")
    }

    private func cancelPollingTasks() {
        for task in pollingTasks.values {
            task.cancel()
        }
        pollingTasks.removeAll()
    }

    // MARK: - Fetch & Update Article

    private func fetchAndUpdateArticle(serverID: String, localID: UUID) async {
        do {
            let dto = try await apiClient.getArticle(id: serverID)

            let articleRepo = ArticleRepository(context: context)
            guard let article = try articleRepo.fetchByID(localID) else { return }

            article.updateFromDTO(dto)

            let merger = ArticleMerger(context: context)
            try merger.resolveRelationships(for: article, from: dto)

            try context.save()
            searchIndexCoordinator.sync(article)
        } catch {
            FolioLogger.sync.error("fetch article detail failed: \(serverID) — \(error)")
        }
    }

    private func updateArticleStatus(localID: UUID, status: ArticleStatus, error: String?) {
        let articleRepo = ArticleRepository(context: context)
        guard let article = try? articleRepo.fetchByID(localID) else { return }
        article.status = status
        article.fetchError = error
        article.updatedAt = Date()
        try? context.save()
    }

    // MARK: - Category Sync

    func syncCategories() async {
        do {
            let response = try await apiClient.listCategories()
            let categoryRepo = CategoryRepository(context: context)

            for dto in response.data {
                if let existing = try categoryRepo.fetchBySlug(dto.slug) {
                    existing.updateFromDTO(dto)
                } else if let byServerID = try categoryRepo.fetchByServerID(dto.id) {
                    byServerID.updateFromDTO(dto)
                }
                // If no local match, skip — server and client have the same preset categories
            }

            try context.save()
        } catch {
            FolioLogger.sync.error("category sync failed: \(error)")
        }
    }

    // MARK: - Tag Sync

    func syncTags() async {
        do {
            let response = try await apiClient.listTags()
            let tagRepo = TagRepository(context: context)

            for dto in response.data {
                if let existing = try tagRepo.fetchByServerID(dto.id) {
                    existing.updateFromDTO(dto)
                } else if let byName = try tagRepo.fetchByName(dto.name) {
                    byName.updateFromDTO(dto)
                } else {
                    let newTag = Tag.fromDTO(dto)
                    context.insert(newTag)
                }
            }

            try context.save()
        } catch {
            FolioLogger.sync.error("tag sync failed: \(error)")
        }
    }

    // MARK: - Full Sync

    func performFullSync() async {
        cancelPollingTasks()
        guard !isSyncing else {
            FolioLogger.sync.debug("full sync skipped — already syncing")
            return
        }
        isSyncing = true
        defer { isSyncing = false }

        FolioLogger.sync.info("starting full sync")
        await syncDeletions()
        await syncPendingUpdates()
        await syncCategories()
        await syncTags()
        await fullSyncArticles()           // Pull server state (including deletions)
        await submitLocalPendingArticles()  // THEN submit remaining pending articles
        await syncUserQuota()
        cleanupOldDeletionRecords()
        searchIndexCoordinator.rebuild(context: context)
        FolioLogger.sync.info("full sync completed")
    }

    // MARK: - Incremental Sync (public entry point)

    func incrementalSync() async {
        cancelPollingTasks()
        guard !isSyncing else {
            FolioLogger.sync.debug("incremental sync skipped — already syncing")
            return
        }
        isSyncing = true
        defer { isSyncing = false }

        await syncDeletions()
        await syncPendingUpdates()
        await incrementalSyncArticles()     // Pull server state (including deletions)
        await submitLocalPendingArticles()  // THEN submit remaining pending articles
        await fetchProcessingArticles()
        searchIndexCoordinator.rebuild(context: context)
    }

    // MARK: - Quota Sync

    private func syncUserQuota() async {
        do {
            let response = try await apiClient.refreshAuth()
            let user = response.user
            let isPro = user.subscription != AppConstants.subscriptionFree
            SharedDataManager.syncQuotaFromServer(
                monthlyQuota: user.monthlyQuota,
                currentMonthCount: user.currentMonthCount,
                isPro: isPro
            )
            // Check epoch from auth response
            if let epoch = user.syncEpoch {
                _ = makeArticlePullSyncWorkflow().checkEpoch(epoch)
            }
        } catch {
            FolioLogger.sync.error("quota sync failed: \(error)")
        }
    }

    // MARK: - Article Sync

    private func makeArticlePullSyncWorkflow() -> ArticlePullSyncWorkflow {
        ArticlePullSyncWorkflow(apiClient: apiClient, context: context, cursorStore: cursorStore)
    }

    private func fullSyncArticles() async {
        await makeArticlePullSyncWorkflow().fullSync()
    }

    private func incrementalSyncArticles() async {
        await makeArticlePullSyncWorkflow().incrementalSync()
    }

    // MARK: - Deletion Sync

    /// Send pending local deletions to the server.
    func syncDeletions() async {
        let descriptor = FetchDescriptor<PendingDeletion>(
            sortBy: [SortDescriptor(\.deletedAt)]
        )
        guard let pending = try? context.fetch(descriptor), !pending.isEmpty else { return }

        FolioLogger.sync.info("syncing \(pending.count) pending deletion(s)")
        for deletion in pending {
            do {
                try await apiClient.deleteArticle(id: deletion.serverID)
                context.delete(deletion)
                FolioLogger.sync.debug("deletion synced: \(deletion.serverID)")
            } catch let error as APIError where error == .notFound {
                // Already deleted on server — clear the pending record
                context.delete(deletion)
            } catch {
                FolioLogger.sync.error("deletion sync failed: \(deletion.serverID) — \(error)")
            }
        }
        try? context.save()
    }

    // MARK: - Pending Update Sync

    /// Retry syncing articles that have local changes not yet sent to server.
    private func syncPendingUpdates() async {
        let workflow = ArticleUpdateSyncWorkflow(apiClient: apiClient, context: context)
        await workflow.syncPendingUpdates()
    }

    // MARK: - Deletion Record Cleanup

    /// Remove DeletionRecords older than retention period.
    private func cleanupOldDeletionRecords() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -DeletionRecord.retentionDays, to: Date()) ?? Date()
        let descriptor = FetchDescriptor<DeletionRecord>(
            predicate: #Predicate<DeletionRecord> { $0.deletedAt < cutoff }
        )
        guard let expired = try? context.fetch(descriptor), !expired.isEmpty else { return }
        for record in expired {
            context.delete(record)
        }
        try? context.save()
        FolioLogger.sync.debug("cleaned up \(expired.count) old deletion record(s)")
    }

    // MARK: - Processing Article Polling

    func fetchProcessingArticles() async {
        let processingRaw = ArticleStatus.processing.rawValue
        let clientReadyRaw = ArticleStatus.clientReady.rawValue
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> {
                $0.statusRaw == processingRaw || $0.statusRaw == clientReadyRaw
            }
        )
        guard let processing = try? context.fetch(descriptor), !processing.isEmpty else { return }

        FolioLogger.sync.debug("fetching \(processing.count) processing articles")
        let merger = ArticleMerger(context: context)
        for article in processing {
            guard let serverID = article.serverID else { continue }
            do {
                let dto = try await apiClient.getArticle(id: serverID)
                article.updateFromDTO(dto)
                try merger.resolveRelationships(for: article, from: dto)
            } catch {
                continue
            }
        }
        try? context.save()
    }
}
