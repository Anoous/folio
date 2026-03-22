import Foundation
import os
import SwiftData

@MainActor
@Observable
final class SyncService {
    private let apiClient: APIClient
    private let context: ModelContext
    private var isSyncing = false

    private static let pollMaxAttempts = 10
    private static let pollInterval: Duration = .seconds(5)
    private static let lastSyncedAtKey = "com.folio.lastSyncedAt"
    private static let lastEpochKey = "com.folio.lastSyncEpoch"

    private var lastEpoch: Int {
        get { UserDefaults.appGroup.integer(forKey: Self.lastEpochKey) }
        set { UserDefaults.appGroup.set(newValue, forKey: Self.lastEpochKey) }
    }

    private var lastSyncedAt: Date? {
        get { UserDefaults.appGroup.object(forKey: Self.lastSyncedAtKey) as? Date }
        set { UserDefaults.appGroup.set(newValue, forKey: Self.lastSyncedAtKey) }
    }

    init(apiClient: APIClient = .shared, context: ModelContext) {
        self.apiClient = apiClient
        self.context = context
    }

    // MARK: - Article Submit

    /// Submit pending articles to the server. Returns a map of article UUID → success.
    func submitPendingArticles(_ articles: [Article]) async -> [UUID: Bool] {
        var results: [UUID: Bool] = [:]

        for article in articles {
            do {
                let response: SubmitArticleResponse
                if article.sourceType == .manual {
                    guard let content = article.markdownContent, !content.isEmpty else {
                        article.status = .failed
                        article.fetchError = "No content to submit"
                        results[article.id] = false
                        continue
                    }
                    response = try await apiClient.submitManualContent(
                        content: content,
                        title: article.title,
                        clientId: article.id.uuidString
                    )
                } else if article.extractionSource == .client {
                    response = try await apiClient.submitArticle(
                        url: article.url,
                        title: article.title,
                        author: article.author,
                        siteName: article.siteName,
                        markdownContent: article.markdownContent,
                        wordCount: article.wordCount > 0 ? article.wordCount : nil
                    )
                } else {
                    response = try await apiClient.submitArticle(url: article.url)
                }
                article.serverID = response.articleId
                article.syncState = .synced
                results[article.id] = true
                FolioLogger.sync.info("article submitted: \(article.url ?? "manual")")

                // Start background polling for this article
                let localID = article.id
                let taskId = response.taskId
                Task {
                    await self.pollTask(taskId: taskId, articleLocalId: localID)
                }
            } catch let error as APIError {
                switch error {
                case .conflict:
                    // Server already has this URL (HTTP 409) — mark as synced
                    article.syncState = .synced
                    article.status = .processing
                    results[article.id] = true
                case .quotaExceeded:
                    FolioLogger.sync.info("quota exceeded for article: \(article.url ?? "manual")")
                    article.status = .failed
                    article.fetchError = "Monthly quota exceeded"
                    results[article.id] = false
                default:
                    FolioLogger.sync.error("submit failed: \(error) — \(article.url ?? "manual")")
                    results[article.id] = false
                }
            } catch {
                FolioLogger.sync.error("submit failed: \(error) — \(article.url ?? "manual")")
                results[article.id] = false
            }
        }

        try? context.save()
        return results
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
        for _ in 0..<Self.pollMaxAttempts {
            try? await Task.sleep(for: Self.pollInterval)

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
                FolioLogger.sync.debug("poll network error: \(error) — task \(taskId)")
                continue
            }
        }

        FolioLogger.sync.error("task polling timed out: \(taskId)")
        updateArticleStatus(localID: articleLocalId, status: .failed, error: "Processing timed out")
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
        FolioLogger.sync.info("full sync completed")
    }

    // MARK: - Incremental Sync (public entry point)

    func incrementalSync() async {
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
                _ = checkEpoch(epoch)
            }
        } catch {
            FolioLogger.sync.error("quota sync failed: \(error)")
        }
    }

    // MARK: - Epoch Check

    /// Purge all locally-synced articles (preserving pending/clientReady that haven't been uploaded).
    private func purgeLocalSyncedArticles() {
        let syncedRaw = SyncState.synced.rawValue
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { $0.syncStateRaw == syncedRaw }
        )
        guard let articles = try? context.fetch(descriptor) else { return }
        for article in articles {
            context.delete(article)
        }

        // Also clear deletion records since they reference a previous epoch
        let deletionDescriptor = FetchDescriptor<DeletionRecord>()
        if let records = try? context.fetch(deletionDescriptor) {
            for record in records {
                context.delete(record)
            }
        }

        try? context.save()
        FolioLogger.sync.info("purged \(articles.count) synced article(s) due to epoch change")
    }

    /// Check the server epoch from a list response. Returns true if epoch is OK (no reset needed).
    private func checkEpoch(_ serverEpoch: Int?) -> Bool {
        guard let serverEpoch, serverEpoch > 0 else { return true }
        let local = lastEpoch
        if local == 0 {
            // First sync ever — just record the epoch
            lastEpoch = serverEpoch
            return true
        }
        if local == serverEpoch {
            return true
        }
        // Epoch mismatch — server data was reset
        FolioLogger.sync.info("epoch mismatch: local=\(local) server=\(serverEpoch), purging")
        purgeLocalSyncedArticles()
        lastSyncedAt = nil
        lastEpoch = serverEpoch
        return false
    }

    // MARK: - Article Sync

    private func syncArticles() async {
        if lastSyncedAt == nil {
            await fullSyncArticles()
        } else {
            await incrementalSyncArticles()
        }
    }

    private func fullSyncArticles() async {
        FolioLogger.sync.info("starting full article sync")
        let merger = ArticleMerger(context: context)
        var page = 1
        let perPage = 50
        var latestServerTime: String?
        var serverIDs: Set<String> = []

        do {
            while true {
                let response = try await apiClient.listArticles(page: page, perPage: perPage)
                if let serverTime = response.serverTime {
                    latestServerTime = serverTime
                }
                // Epoch check on first page
                if page == 1 {
                    _ = checkEpoch(response.syncEpoch)
                }
                for dto in response.data {
                    serverIDs.insert(dto.id)
                    _ = try? merger.merge(dto: dto)
                }
                try? context.save()

                let fetched = (page - 1) * perPage + response.data.count
                if fetched >= response.pagination.total {
                    break
                }
                page += 1
            }
            reconcileLocalArticles(serverIDs: serverIDs)
            lastSyncedAt = parseServerTime(latestServerTime) ?? Date()
            FolioLogger.sync.info("full article sync completed")
        } catch {
            FolioLogger.sync.error("full article sync failed: \(error)")
        }
    }

    /// Delete local synced articles whose serverID is not in the server's full article set.
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

    private func incrementalSyncArticles() async {
        guard let since = lastSyncedAt else {
            await fullSyncArticles()
            return
        }
        FolioLogger.sync.debug("incremental sync since \(since)")
        let merger = ArticleMerger(context: context)
        var page = 1
        let perPage = 50
        var latestServerTime: String?

        do {
            while true {
                let response = try await apiClient.listArticles(
                    page: page, perPage: perPage, updatedSince: since
                )
                if let serverTime = response.serverTime {
                    latestServerTime = serverTime
                }
                // Epoch check on first page
                if page == 1 && !checkEpoch(response.syncEpoch) {
                    // Epoch changed — checkEpoch already purged and reset lastSyncedAt
                    await fullSyncArticles()
                    return
                }
                for dto in response.data {
                    _ = try? merger.merge(dto: dto)
                }
                try? context.save()

                let fetched = (page - 1) * perPage + response.data.count
                if fetched >= response.pagination.total {
                    break
                }
                page += 1
            }
            lastSyncedAt = parseServerTime(latestServerTime) ?? Date()
        } catch {
            FolioLogger.sync.error("incremental sync failed: \(error)")
        }
    }

    private static let serverTimeFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private func parseServerTime(_ timeString: String?) -> Date? {
        guard let timeString else { return nil }
        return Self.serverTimeFormatter.date(from: timeString)
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
        let pendingUpdateRaw = SyncState.pendingUpdate.rawValue
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { $0.syncStateRaw == pendingUpdateRaw }
        )
        guard let articles = try? context.fetch(descriptor), !articles.isEmpty else { return }

        FolioLogger.sync.info("syncing \(articles.count) pending update(s)")
        for article in articles {
            guard let serverID = article.serverID else { continue }
            do {
                try await apiClient.updateArticle(id: serverID, request: UpdateArticleRequest(
                    isFavorite: article.isFavorite,
                    isArchived: article.isArchived,
                    readProgress: article.readProgress
                ))
                article.syncState = .synced
            } catch let error as APIError where error == .notFound {
                // Server no longer has this article.
                // Keep serverID so ArticleMerger can still match if the server
                // sends a deletion notification (multi-device delete scenario).
                // Mark as pendingUpload; submitLocalPendingArticles will re-upload
                // only if incrementalSync didn't delete it first.
                FolioLogger.sync.info("article gone from server, marking for re-upload: \(serverID)")
                article.syncState = .pendingUpload
                if article.markdownContent != nil {
                    article.extractionSource = .client
                    article.status = .clientReady
                } else {
                    article.status = .pending
                }
            } catch {
                FolioLogger.sync.error("update sync failed: \(serverID) — \(error)")
            }
        }
        try? context.save()
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
