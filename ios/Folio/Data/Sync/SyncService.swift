import Foundation
import os
import SwiftData

@MainActor
@Observable
final class SyncService {
    private let apiClient: APIClient
    private let context: ModelContext

    private static let pollMaxAttempts = 10
    private static let pollIntervalNanoseconds: UInt64 = 5_000_000_000
    private static let lastSyncedAtKey = "com.folio.lastSyncedAt"

    private var lastSyncedAt: Date? {
        get { UserDefaults.standard.object(forKey: Self.lastSyncedAtKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Self.lastSyncedAtKey) }
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
                if article.extractionSource == .client {
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
                FolioLogger.sync.info("article submitted: \(article.url)")

                // Start background polling for this article
                let localID = article.id
                let taskId = response.taskId
                Task {
                    await self.pollTask(taskId: taskId, articleLocalId: localID)
                }
            } catch let error as APIError {
                switch error {
                case .serverMessage(let msg) where msg.contains("already saved"):
                    // Server already has this URL — mark as synced
                    article.syncState = .synced
                    article.status = .processing
                    results[article.id] = true
                case .quotaExceeded:
                    FolioLogger.sync.info("quota exceeded for article: \(article.url)")
                    article.status = .failed
                    article.fetchError = "Monthly quota exceeded"
                    results[article.id] = false
                default:
                    FolioLogger.sync.error("submit failed: \(error) — \(article.url)")
                    results[article.id] = false
                }
            } catch {
                FolioLogger.sync.error("submit failed: \(error) — \(article.url)")
                results[article.id] = false
            }
        }

        try? context.save()
        return results
    }

    // MARK: - Task Polling

    private func pollTask(taskId: String, articleLocalId: UUID) async {
        for _ in 0..<Self.pollMaxAttempts {
            try? await Task.sleep(nanoseconds: Self.pollIntervalNanoseconds)

            do {
                let task = try await apiClient.getTask(id: taskId)

                switch task.status {
                case "done":
                    FolioLogger.sync.info("task done: \(taskId)")
                    if let articleId = task.articleId {
                        await fetchAndUpdateArticle(serverID: articleId, localID: articleLocalId)
                    }
                    return
                case "failed":
                    FolioLogger.sync.error("task failed: \(taskId) — \(task.errorMessage ?? "unknown")")
                    updateArticleStatus(localID: articleLocalId, status: .failed, error: task.errorMessage)
                    return
                case "queued", "crawling", "ai_processing":
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
        FolioLogger.sync.info("starting full sync")
        await syncCategories()
        await syncTags()
        await syncArticles()
        await syncUserQuota()
        FolioLogger.sync.info("full sync completed")
    }

    // MARK: - Incremental Sync (public entry point)

    func incrementalSync() async {
        await incrementalSyncArticles()
        await fetchProcessingArticles()
    }

    // MARK: - Quota Sync

    private func syncUserQuota() async {
        do {
            let response = try await apiClient.refreshAuth()
            let user = response.user
            let isPro = user.subscription != "free"
            SharedDataManager.syncQuotaFromServer(
                monthlyQuota: user.monthlyQuota,
                currentMonthCount: user.currentMonthCount,
                isPro: isPro
            )
        } catch {
            FolioLogger.sync.error("quota sync failed: \(error)")
        }
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

        do {
            while true {
                let response = try await apiClient.listArticles(page: page, perPage: perPage)
                for dto in response.data {
                    try? merger.merge(dto: dto)
                }
                try? context.save()

                let fetched = (page - 1) * perPage + response.data.count
                if fetched >= response.pagination.total {
                    break
                }
                page += 1
            }
            lastSyncedAt = Date()
            FolioLogger.sync.info("full article sync completed")
        } catch {
            FolioLogger.sync.error("full article sync failed: \(error)")
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

        do {
            while true {
                let response = try await apiClient.listArticles(
                    page: page, perPage: perPage, updatedSince: since
                )
                for dto in response.data {
                    try? merger.merge(dto: dto)
                }
                try? context.save()

                let fetched = (page - 1) * perPage + response.data.count
                if fetched >= response.pagination.total {
                    break
                }
                page += 1
            }
            lastSyncedAt = Date()
        } catch {
            FolioLogger.sync.error("incremental sync failed: \(error)")
        }
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
