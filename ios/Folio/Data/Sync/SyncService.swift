import Foundation
import SwiftData

@MainActor
final class SyncService {
    private let apiClient: APIClient
    private let context: ModelContext

    private static let pollMaxAttempts = 30
    private static let pollIntervalNanoseconds: UInt64 = 3_000_000_000

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

                // Start background polling for this article
                let localID = article.id
                let taskId = response.taskId
                Task {
                    await self.pollTask(taskId: taskId, articleLocalId: localID)
                }
            } catch APIError.quotaExceeded {
                article.status = .failed
                article.fetchError = "Monthly quota exceeded"
                results[article.id] = false
            } catch {
                // Keep pending for retry on next network event
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
                    if let articleId = task.articleId {
                        await fetchAndUpdateArticle(serverID: articleId, localID: articleLocalId)
                    }
                    return
                case "failed":
                    updateArticleStatus(localID: articleLocalId, status: .failed, error: task.errorMessage)
                    return
                case "queued", "crawling", "ai_processing":
                    continue
                default:
                    continue
                }
            } catch {
                // Network error during polling — continue retrying
                continue
            }
        }

        // Timed out — mark as failed
        updateArticleStatus(localID: articleLocalId, status: .failed, error: "Processing timed out")
    }

    // MARK: - Fetch & Update Article

    private func fetchAndUpdateArticle(serverID: String, localID: UUID) async {
        do {
            let dto = try await apiClient.getArticle(id: serverID)

            let articleRepo = ArticleRepository(context: context)
            guard let article = try articleRepo.fetchByID(localID) else { return }

            article.updateFromDTO(dto)

            // Resolve category
            if let categoryDTO = dto.category {
                let categoryRepo = CategoryRepository(context: context)
                if let localCategory = try categoryRepo.fetchBySlug(categoryDTO.slug) {
                    localCategory.updateFromDTO(categoryDTO)
                    article.category = localCategory
                }
            }

            // Resolve tags
            if let tagDTOs = dto.tags {
                let tagRepo = TagRepository(context: context)
                var resolvedTags: [Tag] = []
                for tagDTO in tagDTOs {
                    if let existing = try tagRepo.fetchByServerID(tagDTO.id) {
                        existing.updateFromDTO(tagDTO)
                        resolvedTags.append(existing)
                    } else if let byName = try tagRepo.fetchByName(tagDTO.name) {
                        byName.updateFromDTO(tagDTO)
                        resolvedTags.append(byName)
                    } else {
                        let newTag = Tag.fromDTO(tagDTO)
                        context.insert(newTag)
                        resolvedTags.append(newTag)
                    }
                }
                article.tags = resolvedTags
            }

            try context.save()
        } catch {
            // Failed to fetch/update — article retains its current state
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
            // Category sync failed — non-critical, will retry on next sign-in
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
            // Tag sync failed — non-critical
        }
    }

    // MARK: - Full Sync

    func performFullSync() async {
        await syncCategories()
        await syncTags()
    }
}
