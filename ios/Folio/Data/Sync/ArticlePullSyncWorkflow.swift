import Foundation
import SwiftData

@MainActor
final class ArticlePullSyncWorkflow {
    private static let perPage = 50

    private static let serverTimeFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private let apiClient: APIClient
    private let context: ModelContext
    private let cursorStore: ArticleSyncCursorStore

    init(
        apiClient: APIClient,
        context: ModelContext,
        cursorStore: ArticleSyncCursorStore = ArticleSyncCursorStore()
    ) {
        self.apiClient = apiClient
        self.context = context
        self.cursorStore = cursorStore
    }

    func fullSync() async {
        FolioLogger.sync.info("starting full article sync")
        let merger = ArticleMerger(context: context)
        var page = 1
        var latestServerTime: String?
        var serverIDs: Set<String> = []

        do {
            while true {
                let response = try await apiClient.listArticles(page: page, perPage: Self.perPage)
                if let serverTime = response.serverTime {
                    latestServerTime = serverTime
                }
                if page == 1 {
                    _ = checkEpoch(response.syncEpoch)
                }
                for dto in response.data {
                    serverIDs.insert(dto.id)
                    _ = try? merger.merge(dto: dto)
                }
                try? context.save()

                let fetched = (page - 1) * Self.perPage + response.data.count
                if fetched >= response.pagination.total {
                    break
                }
                page += 1
            }
            reconcileLocalArticles(serverIDs: serverIDs)
            cursorStore.lastSyncedAt = parseServerTime(latestServerTime) ?? Date()
            FolioLogger.sync.info("full article sync completed")
        } catch {
            FolioLogger.sync.error("full article sync failed: \(error)")
        }
    }

    func incrementalSync() async {
        guard let since = cursorStore.lastSyncedAt else {
            await fullSync()
            return
        }
        FolioLogger.sync.debug("incremental sync since \(since)")
        let merger = ArticleMerger(context: context)
        var page = 1
        var latestServerTime: String?

        do {
            while true {
                let response = try await apiClient.listArticles(
                    page: page,
                    perPage: Self.perPage,
                    updatedSince: since
                )
                if let serverTime = response.serverTime {
                    latestServerTime = serverTime
                }
                if page == 1 && !checkEpoch(response.syncEpoch) {
                    await fullSync()
                    return
                }
                for dto in response.data {
                    _ = try? merger.merge(dto: dto)
                }
                try? context.save()

                let fetched = (page - 1) * Self.perPage + response.data.count
                if fetched >= response.pagination.total {
                    break
                }
                page += 1
            }
            cursorStore.lastSyncedAt = parseServerTime(latestServerTime) ?? Date()
        } catch {
            FolioLogger.sync.error("incremental sync failed: \(error)")
        }
    }

    @discardableResult
    func checkEpoch(_ serverEpoch: Int?) -> Bool {
        guard let serverEpoch, serverEpoch > 0 else { return true }
        let local = cursorStore.lastEpoch
        if local == 0 {
            cursorStore.lastEpoch = serverEpoch
            return true
        }
        if local == serverEpoch {
            return true
        }

        FolioLogger.sync.info("epoch mismatch: local=\(local) server=\(serverEpoch), purging")
        purgeLocalSyncedArticles()
        cursorStore.lastSyncedAt = nil
        cursorStore.lastEpoch = serverEpoch
        return false
    }

    /// Purge all locally-synced articles while preserving pending/clientReady articles that have not uploaded.
    private func purgeLocalSyncedArticles() {
        let syncedRaw = SyncState.synced.rawValue
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { $0.syncStateRaw == syncedRaw }
        )
        guard let articles = try? context.fetch(descriptor) else { return }
        for article in articles {
            context.delete(article)
        }

        let deletionDescriptor = FetchDescriptor<DeletionRecord>()
        if let records = try? context.fetch(deletionDescriptor) {
            for record in records {
                context.delete(record)
            }
        }

        try? context.save()
        FolioLogger.sync.info("purged \(articles.count) synced article(s) due to epoch change")
    }

    /// Delete local synced articles whose serverID is not in the server's full article set.
    private func reconcileLocalArticles(serverIDs: Set<String>) {
        let syncedRaw = SyncState.synced.rawValue
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { $0.syncStateRaw == syncedRaw && $0.serverID != nil }
        )
        guard let localArticles = try? context.fetch(descriptor) else { return }

        var removedCount = 0
        for article in localArticles {
            guard let sid = article.serverID else { continue }
            if !serverIDs.contains(sid) {
                context.delete(article)
                removedCount += 1
            }
        }
        if removedCount > 0 {
            try? context.save()
            FolioLogger.sync.info("reconciliation: removed \(removedCount) orphaned article(s)")
        }
    }

    private func parseServerTime(_ timeString: String?) -> Date? {
        guard let timeString else { return nil }
        return Self.serverTimeFormatter.date(from: timeString)
    }
}
