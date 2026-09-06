@MainActor
struct SyncRunWorkflow {
    enum RunKind {
        case full
        case incremental
    }

    struct Operations {
        let cancelPollingTasks: () -> Void
        let syncDeletions: () async -> Void
        let syncPendingUpdates: () async -> Void
        let syncCategories: () async -> Void
        let syncTags: () async -> Void
        let fullSyncArticles: () async -> Void
        let incrementalSyncArticles: () async -> Void
        let submitLocalPendingArticles: () async -> Void
        let syncUserQuota: () async -> Void
        let cleanupOldDeletionRecords: () -> Void
        let fetchProcessingArticles: () async -> Void
        let rebuildSearchIndex: () -> Void
    }

    let operations: Operations

    func run(_ kind: RunKind) async {
        operations.cancelPollingTasks()

        switch kind {
        case .full:
            await operations.syncDeletions()
            await operations.syncPendingUpdates()
            await operations.syncCategories()
            await operations.syncTags()
            await operations.fullSyncArticles()
            await operations.submitLocalPendingArticles()
            await operations.syncUserQuota()
            operations.cleanupOldDeletionRecords()
            operations.rebuildSearchIndex()
        case .incremental:
            await operations.syncDeletions()
            await operations.syncPendingUpdates()
            await operations.incrementalSyncArticles()
            await operations.submitLocalPendingArticles()
            await operations.fetchProcessingArticles()
            operations.rebuildSearchIndex()
        }
    }
}
