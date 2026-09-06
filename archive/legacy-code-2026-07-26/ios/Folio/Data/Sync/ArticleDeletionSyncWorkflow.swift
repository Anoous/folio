import Foundation
import SwiftData

@MainActor
final class ArticleDeletionSyncWorkflow {
    private let apiClient: APIClient
    private let context: ModelContext

    init(apiClient: APIClient, context: ModelContext) {
        self.apiClient = apiClient
        self.context = context
    }

    func syncPendingDeletions() async {
        let descriptor = FetchDescriptor<PendingDeletion>(
            sortBy: [SortDescriptor(\.deletedAt)]
        )
        guard let pending = try? context.fetch(descriptor), !pending.isEmpty else { return }

        FolioLogger.sync.info("syncing \(pending.count) pending deletion(s)")
        for deletion in pending {
            await syncPendingDeletion(deletion)
        }
        try? context.save()
    }

    func cleanupOldDeletionRecords(now: Date = Date(), calendar: Calendar = .current) {
        let cutoff = calendar.date(
            byAdding: .day,
            value: -DeletionRecord.retentionDays,
            to: now
        ) ?? now
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

    private func syncPendingDeletion(_ deletion: PendingDeletion) async {
        do {
            try await apiClient.deleteArticle(id: deletion.serverID)
            context.delete(deletion)
            FolioLogger.sync.debug("deletion synced: \(deletion.serverID)")
        } catch let error as APIError where error == .notFound {
            context.delete(deletion)
        } catch {
            FolioLogger.sync.error("deletion sync failed: \(deletion.serverID) — \(error)")
        }
    }
}
