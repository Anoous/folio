import Foundation
import Observation
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
        await makeArticleSyncWorkflow()
            .submitPendingArticles(articles, onTaskStarted: taskStartedHandler())
    }

    private func submitLocalPendingArticles() async {
        _ = await makeArticleSyncWorkflow().submitLocalPendingArticles(onTaskStarted: taskStartedHandler())
    }

    private func makeArticleSyncWorkflow() -> ArticleSyncWorkflow {
        ArticleSyncWorkflow(apiClient: apiClient, context: context)
    }

    private func taskStartedHandler() -> ArticleSyncWorkflow.TaskStartedHandler {
        { [weak self] localID, taskID in
            guard let self else { return }
            self.articleProcessingSyncWorkflow.startPolling(taskID: taskID, articleLocalID: localID)
        }
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
        guard !isSyncing else {
            cancelPollingTasks()
            FolioLogger.sync.debug("full sync skipped — already syncing")
            return
        }
        isSyncing = true
        defer { isSyncing = false }

        FolioLogger.sync.info("starting full sync")
        await makeSyncRunWorkflow().run(.full)
        FolioLogger.sync.info("full sync completed")
    }

    // MARK: - Incremental Sync (public entry point)

    func incrementalSync() async {
        guard !isSyncing else {
            cancelPollingTasks()
            FolioLogger.sync.debug("incremental sync skipped — already syncing")
            return
        }
        isSyncing = true
        defer { isSyncing = false }

        await makeSyncRunWorkflow().run(.incremental)
    }

    private func makeSyncRunWorkflow() -> SyncRunWorkflow {
        SyncRunWorkflow(operations: .init(
            cancelPollingTasks: { [weak self] in
                self?.cancelPollingTasks()
            },
            syncDeletions: { [weak self] in
                guard let self else { return }
                await self.syncDeletions()
            },
            syncPendingUpdates: { [weak self] in
                guard let self else { return }
                await self.syncPendingUpdates()
            },
            syncCategories: { [weak self] in
                guard let self else { return }
                await self.syncCategories()
            },
            syncTags: { [weak self] in
                guard let self else { return }
                await self.syncTags()
            },
            fullSyncArticles: { [weak self] in
                guard let self else { return }
                await self.fullSyncArticles()
            },
            incrementalSyncArticles: { [weak self] in
                guard let self else { return }
                await self.incrementalSyncArticles()
            },
            submitLocalPendingArticles: { [weak self] in
                guard let self else { return }
                await self.submitLocalPendingArticles()
            },
            syncUserQuota: { [weak self] in
                guard let self else { return }
                await self.syncUserQuota()
            },
            cleanupOldDeletionRecords: { [weak self] in
                self?.cleanupOldDeletionRecords()
            },
            fetchProcessingArticles: { [weak self] in
                guard let self else { return }
                await self.fetchProcessingArticles()
            },
            rebuildSearchIndex: { [weak self] in
                guard let self else { return }
                self.searchIndexCoordinator.rebuild(context: self.context)
            }
        ))
    }

    // MARK: - Quota Sync

    private func syncUserQuota() async {
        await makeUserQuotaSyncWorkflow().syncUserQuota()
    }

    private func makeUserQuotaSyncWorkflow() -> UserQuotaSyncWorkflow {
        UserQuotaSyncWorkflow(apiClient: apiClient, epochChecker: { [weak self] epoch in
            guard let self else { return }
            _ = self.makeArticlePullSyncWorkflow().checkEpoch(epoch)
        })
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
