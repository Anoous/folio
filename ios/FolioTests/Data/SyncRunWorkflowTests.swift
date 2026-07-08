import XCTest
@testable import Folio

final class SyncRunWorkflowTests: XCTestCase {
    @MainActor
    func testFullRunOwnsSyncOrdering() async {
        var events: [String] = []
        let workflow = SyncRunWorkflow(operations: .init(
            cancelPollingTasks: { events.append("cancelPolling") },
            syncDeletions: { events.append("deletions") },
            syncPendingUpdates: { events.append("updates") },
            syncCategories: { events.append("categories") },
            syncTags: { events.append("tags") },
            fullSyncArticles: { events.append("fullArticles") },
            incrementalSyncArticles: { events.append("incrementalArticles") },
            submitLocalPendingArticles: { events.append("submitPending") },
            syncUserQuota: { events.append("quota") },
            cleanupOldDeletionRecords: { events.append("cleanup") },
            fetchProcessingArticles: { events.append("processing") },
            rebuildSearchIndex: { events.append("rebuildIndex") }
        ))

        await workflow.run(.full)

        XCTAssertEqual(events, [
            "cancelPolling",
            "deletions",
            "updates",
            "categories",
            "tags",
            "fullArticles",
            "submitPending",
            "quota",
            "cleanup",
            "rebuildIndex",
        ])
    }

    @MainActor
    func testIncrementalRunOwnsSyncOrdering() async {
        var events: [String] = []
        let workflow = SyncRunWorkflow(operations: .init(
            cancelPollingTasks: { events.append("cancelPolling") },
            syncDeletions: { events.append("deletions") },
            syncPendingUpdates: { events.append("updates") },
            syncCategories: { events.append("categories") },
            syncTags: { events.append("tags") },
            fullSyncArticles: { events.append("fullArticles") },
            incrementalSyncArticles: { events.append("incrementalArticles") },
            submitLocalPendingArticles: { events.append("submitPending") },
            syncUserQuota: { events.append("quota") },
            cleanupOldDeletionRecords: { events.append("cleanup") },
            fetchProcessingArticles: { events.append("processing") },
            rebuildSearchIndex: { events.append("rebuildIndex") }
        ))

        await workflow.run(.incremental)

        XCTAssertEqual(events, [
            "cancelPolling",
            "deletions",
            "updates",
            "incrementalArticles",
            "submitPending",
            "processing",
            "rebuildIndex",
        ])
    }
}
