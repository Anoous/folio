import Foundation
import SwiftData
import SwiftUI

@MainActor
@Observable
final class HomeViewModel {
    private let context: ModelContext
    private let apiClient: APIClient

    var articles: [Article] = []
    var groupedArticles: [(String, [Article])] = []
    var selectedCategory: Folio.Category?
    var selectedTags: [Tag] = []
    var isLoading = false
    var isAuthenticated = false
    var syncError: String?
    var showToast = false
    var toastMessage = ""
    var toastIcon: String? = nil

    private var currentPage = 0
    private let pageSize = 20
    private var hasMorePages = true

    init(context: ModelContext, isAuthenticated: Bool = false, apiClient: APIClient = .shared) {
        self.context = context
        self.isAuthenticated = isAuthenticated
        self.apiClient = apiClient
    }

    func fetchArticles() {
        currentPage = 0
        hasMorePages = true
        loadPage(reset: true)
    }

    func loadNextPage() {
        guard hasMorePages, !isLoading else { return }
        loadPage(reset: false)
    }

    func markAsRead(_ article: Article) {
        if article.readProgress == 0 {
            article.readProgress = 0.01
        }
        article.lastReadAt = Date()
        article.updatedAt = Date()
        try? context.save()
    }

    // MARK: - Server Refresh

    func refreshFromServer() async {
        guard isAuthenticated else {
            fetchArticles()
            return
        }

        isLoading = true
        syncError = nil

        do {
            let response = try await apiClient.listArticles(page: 1, perPage: 20, status: "ready")
            let needsDetail = mergeServerArticles(response.data)
            await fetchMissingContent(needsDetail)
        } catch {
            syncError = error.localizedDescription
        }

        fetchArticles()
        isLoading = false
    }

    // MARK: - Merge Server Articles

    /// Merges server DTOs into local store. Returns server IDs of articles
    /// that are ready on the server but missing local markdown content.
    @discardableResult
    private func mergeServerArticles(_ dtos: [ArticleDTO]) -> [String] {
        let articleRepo = ArticleRepository(context: context)
        let tagRepo = TagRepository(context: context)
        let categoryRepo = CategoryRepository(context: context)
        var needsDetail: [String] = []

        for dto in dtos {
            let article: Article

            // Try to find existing by serverID
            if let existing = try? articleRepo.fetchByServerID(dto.id) {
                existing.updateFromDTO(dto)
                article = existing
            } else if let byURL = try? articleRepo.fetchByURL(dto.url) {
                // Found by URL — link serverID and update
                byURL.updateFromDTO(dto)
                article = byURL
            } else {
                // New article from server
                let newArticle = Article.fromDTO(dto)
                context.insert(newArticle)
                article = newArticle
            }

            // Resolve category
            if let categoryDTO = dto.category {
                if let localCategory = try? categoryRepo.fetchBySlug(categoryDTO.slug) {
                    localCategory.updateFromDTO(categoryDTO)
                    article.category = localCategory
                }
            }

            // Resolve tags
            if let tagDTOs = dto.tags {
                var resolvedTags: [Tag] = []
                for tagDTO in tagDTOs {
                    if let existing = try? tagRepo.fetchByServerID(tagDTO.id) {
                        existing.updateFromDTO(tagDTO)
                        resolvedTags.append(existing)
                    } else if let byName = try? tagRepo.fetchByName(tagDTO.name) {
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

            // Article is ready on server but local content is missing
            if dto.status == "ready" && article.markdownContent == nil {
                needsDetail.append(dto.id)
            }
        }

        try? context.save()
        return needsDetail
    }

    // MARK: - Fetch Missing Content

    /// Fetches full article details for articles missing markdown content.
    private func fetchMissingContent(_ serverIDs: [String]) async {
        guard !serverIDs.isEmpty else { return }

        let articleRepo = ArticleRepository(context: context)
        let tagRepo = TagRepository(context: context)
        let categoryRepo = CategoryRepository(context: context)

        for serverID in serverIDs {
            do {
                let dto = try await apiClient.getArticle(id: serverID)
                guard let article = try? articleRepo.fetchByServerID(serverID) else { continue }

                article.updateFromDTO(dto)

                if let categoryDTO = dto.category {
                    if let localCategory = try? categoryRepo.fetchBySlug(categoryDTO.slug) {
                        localCategory.updateFromDTO(categoryDTO)
                        article.category = localCategory
                    }
                }

                if let tagDTOs = dto.tags {
                    var resolvedTags: [Tag] = []
                    for tagDTO in tagDTOs {
                        if let existing = try? tagRepo.fetchByServerID(tagDTO.id) {
                            existing.updateFromDTO(tagDTO)
                            resolvedTags.append(existing)
                        } else if let byName = try? tagRepo.fetchByName(tagDTO.name) {
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
            } catch {
                // Failed to fetch detail — will retry on next refresh
                continue
            }
        }

        try? context.save()
    }

    // MARK: - Article Actions

    func toggleFavorite(_ article: Article) {
        let previousValue = article.isFavorite
        article.isFavorite.toggle()
        article.updatedAt = Date()
        try? context.save()

        if article.isFavorite {
            showToastMessage(String(localized: "home.article.favorited", defaultValue: "Added to favorites"), icon: "heart.fill")
        } else {
            showToastMessage(String(localized: "home.article.unfavorited", defaultValue: "Removed from favorites"), icon: "heart")
        }

        if isAuthenticated, let serverID = article.serverID {
            Task {
                do {
                    try await apiClient.updateArticle(
                        id: serverID,
                        request: UpdateArticleRequest(isFavorite: article.isFavorite)
                    )
                    article.syncState = .synced
                } catch {
                    // Rollback on failure
                    article.isFavorite = previousValue
                    article.syncState = .pendingUpdate
                    try? context.save()
                    showToastMessage(String(localized: "home.article.syncFailed", defaultValue: "Sync failed, will retry"), icon: "exclamationmark.icloud")
                }
            }
        }
    }

    func archiveArticle(_ article: Article) {
        let previousValue = article.isArchived
        article.isArchived.toggle()
        article.updatedAt = Date()
        try? context.save()

        if article.isArchived {
            showToastMessage(String(localized: "home.article.archived", defaultValue: "Archived"), icon: "archivebox.fill")
        } else {
            showToastMessage(String(localized: "home.article.unarchived", defaultValue: "Unarchived"), icon: "archivebox")
        }

        if isAuthenticated, let serverID = article.serverID {
            Task {
                do {
                    try await apiClient.updateArticle(
                        id: serverID,
                        request: UpdateArticleRequest(isArchived: article.isArchived)
                    )
                    article.syncState = .synced
                } catch {
                    // Rollback on failure
                    article.isArchived = previousValue
                    article.syncState = .pendingUpdate
                    try? context.save()
                    showToastMessage(String(localized: "home.article.syncFailed", defaultValue: "Sync failed, will retry"), icon: "exclamationmark.icloud")
                }
            }
        }
    }

    func deleteArticle(_ article: Article) {
        let serverID = article.serverID

        context.delete(article)
        try? context.save()
        fetchArticles()

        showToastMessage(String(localized: "home.article.deleted", defaultValue: "Article deleted"), icon: "trash")

        if isAuthenticated, let serverID {
            Task { try? await apiClient.deleteArticle(id: serverID) }
        }
    }

    // MARK: - Retry Failed Article

    func retryArticle(_ article: Article) {
        article.status = .pending
        article.fetchError = nil
        article.retryCount += 1
        article.updatedAt = Date()
        try? context.save()
        fetchArticles()

        showToastMessage(String(localized: "home.article.retrying", defaultValue: "Retrying..."), icon: "arrow.clockwise")

        if isAuthenticated {
            Task {
                do {
                    // Re-submit URL to server for processing
                    let response = try await apiClient.submitArticle(url: article.url)
                    article.serverID = response.articleId
                    article.status = .processing
                } catch {
                    article.status = .failed
                    article.fetchError = error.localizedDescription
                }
                try? context.save()
                fetchArticles()
            }
        }
    }

    // MARK: - Dismiss Sync Error

    func dismissSyncError() {
        syncError = nil
    }

    // MARK: - Toast

    private func showToastMessage(_ message: String, icon: String? = nil) {
        toastMessage = message
        toastIcon = icon
        showToast = true
    }

    // MARK: - Private

    private func loadPage(reset: Bool) {
        isLoading = true

        var descriptor = FetchDescriptor<Article>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = pageSize
        descriptor.fetchOffset = currentPage * pageSize

        guard var fetched = try? context.fetch(descriptor) else {
            isLoading = false
            return
        }

        // Apply filters
        if let category = selectedCategory {
            fetched = fetched.filter { $0.category?.id == category.id }
        }
        if !selectedTags.isEmpty {
            let tagIDs = Set(selectedTags.map(\.id))
            fetched = fetched.filter { article in
                tagIDs.isSubset(of: Set(article.tags.map(\.id)))
            }
        }

        if reset {
            articles = fetched
        } else {
            articles.append(contentsOf: fetched)
        }

        hasMorePages = fetched.count == pageSize
        currentPage += 1
        groupedArticles = groupByDate(articles)
        isLoading = false
    }

    func groupByDate(_ articles: [Article]) -> [(String, [Article])] {
        let calendar = Calendar.current
        var groups: [String: [Article]] = [:]
        var order: [String] = []

        let dateFormatter: DateFormatter = {
            let f = DateFormatter()
            f.doesRelativeDateFormatting = false
            f.dateStyle = .medium
            f.timeStyle = .none
            return f
        }()

        for article in articles {
            let key: String
            if calendar.isDateInToday(article.createdAt) {
                key = String(localized: "today", defaultValue: "Today")
            } else if calendar.isDateInYesterday(article.createdAt) {
                key = String(localized: "yesterday", defaultValue: "Yesterday")
            } else {
                key = dateFormatter.string(from: article.createdAt)
            }

            if groups[key] == nil {
                order.append(key)
            }
            groups[key, default: []].append(article)
        }

        return order.compactMap { key in
            guard let items = groups[key] else { return nil }
            return (key, items)
        }
    }
}
