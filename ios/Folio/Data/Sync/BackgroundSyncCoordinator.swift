import Foundation
import SwiftData

@MainActor
enum BackgroundSyncCoordinator {
    static func pendingArticleCount(in context: ModelContext) -> Int {
        let pendingRaw = ArticleStatus.pending.rawValue
        let clientReadyRaw = ArticleStatus.clientReady.rawValue
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { $0.statusRaw == pendingRaw || $0.statusRaw == clientReadyRaw }
        )
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    static func performPendingSyncIfNeeded(
        context: ModelContext,
        isAuthenticated: Bool,
        sync: @escaping @MainActor () async -> Void
    ) async -> Bool {
        guard isAuthenticated else {
            FolioLogger.sync.debug("background sync skipped — not authenticated")
            return true
        }

        let pendingCount = pendingArticleCount(in: context)
        guard pendingCount > 0 else {
            FolioLogger.sync.debug("background sync skipped — no pending local work")
            return true
        }

        await sync()
        return !Task.isCancelled
    }

    static func runPendingSyncIfNeeded(
        apiClient: APIClient = .shared,
        keychainManager: KeyChainManager = .shared
    ) async -> Bool {
        guard !Task.isCancelled else { return false }

        do {
            let container = try DataManager.createSharedContainer()
            let context = container.mainContext
            let isAuthenticated = keychainManager.hasStoredSession

            return await performPendingSyncIfNeeded(context: context, isAuthenticated: isAuthenticated) {
                let syncService = SyncService(apiClient: apiClient, context: context)
                await syncService.incrementalSync()
            }
        } catch {
            FolioLogger.sync.error("background sync bootstrap failed: \(error)")
            return false
        }
    }
}
