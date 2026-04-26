import Foundation
import os
import SwiftData

@MainActor
@Observable
final class SyncService {
    private let apiClient: APIClient
    private let context: ModelContext
    private let searchIndexCoordinator: SearchIndexCoordinator
    private let articleProcessingSyncWorkflow: ArticleProcessingSyncWorkflow
    private let cursorStore: ArticleSyncCursorStore
    private var isSyncing = false

    init(
        apiClient: APIClient = .shared,
        context: ModelContext,
        searchIndexCoordinator: SearchIndexCoordinator? = nil,
        cursorStore: ArticleSyncCursorStore = ArticleSyncCursorStore()
    ) {
        self.apiClient = apiClient
        self.context = context
        let resolvedSearchIndexCoordinator = searchIndexCoordinator ?? .shared
        self.searchIndexCoordinator = resolvedSearchIndexCoordinator
        self.articleProcessingSyncWorkflow = ArticleProcessingSyncWorkflow(
            apiClient: apiClient,
            context: context,
            searchIndexCoordinator: resolvedSearchIndexCoordinator
        )
        self.cursorStore = cursorStore
    }

    // MARK: - Article Submit

    /// Submit pending articles to the server. Returns a map of article UUID → success.
    func submitPendingArticles(_ articles: [Article]) async -> [UUID: Bool] {
        let workflow = ArticleSyncWorkflow(apiClient: apiClient, context: context)
        return await workflow.submitPendingArticles(articles) { [weak self] localID, taskID in
            guard let self else { return }
            self.articleProcessingSyncWorkflow.startPolling(taskID: taskID, articleLocalID: localID)
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

    private func cancelPollingTasks() {
        articleProcessingSyncWorkflow.cancelPollingTasks()
    }

    // MARK: - Taxonomy Sync

    private func makeTaxonomySyncWorkflow() -> TaxonomySyncWorkflow {
        TaxonomySyncWorkflow(apiClient: apiClient, context: context)
    }

    func syncCategories() async {
        await makeTaxonomySyncWorkflow().syncCategories()
    }

    func syncTags() async {
        await makeTaxonomySyncWorkflow().syncTags()
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

    private func makeArticleDeletionSyncWorkflow() -> ArticleDeletionSyncWorkflow {
        ArticleDeletionSyncWorkflow(apiClient: apiClient, context: context)
    }

    /// Send pending local deletions to the server.
    func syncDeletions() async {
        await makeArticleDeletionSyncWorkflow().syncPendingDeletions()
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
        makeArticleDeletionSyncWorkflow().cleanupOldDeletionRecords()
    }

    // MARK: - Processing Article Polling

    func fetchProcessingArticles() async {
        await articleProcessingSyncWorkflow.refreshProcessingArticles()
    }
}
