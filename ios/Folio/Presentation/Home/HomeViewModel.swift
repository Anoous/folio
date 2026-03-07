import Foundation
import os
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
        article.markAsRead(in: context)
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
            let response = try await apiClient.listArticles(page: 1, perPage: 50)
            let needsDetail = mergeServerArticles(response.data)
            await fetchMissingContent(needsDetail)
        } catch {
            FolioLogger.sync.error("refreshFromServer failed: \(error)")
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
        let merger = ArticleMerger(context: context)
        var needsDetail: [String] = []

        for dto in dtos {
            guard let article = try? merger.merge(dto: dto) else { continue }

            // Article is ready on server but local content is missing
            if dto.status == ArticleStatus.ready.rawValue && article.markdownContent == nil {
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
        let merger = ArticleMerger(context: context)

        for serverID in serverIDs {
            do {
                let dto = try await apiClient.getArticle(id: serverID)
                guard let article = try? articleRepo.fetchByServerID(serverID) else { continue }

                article.updateFromDTO(dto)
                try merger.resolveRelationships(for: article, from: dto)
            } catch {
                // Failed to fetch detail — will retry on next refresh
                continue
            }
        }

        try? context.save()
    }

    // MARK: - Article Actions

    func toggleFavorite(_ article: Article) {
        article.toggleFavoriteWithSync(
            context: context, apiClient: apiClient,
            isAuthenticated: isAuthenticated, showToast: showToastMessage
        )
    }

    func archiveArticle(_ article: Article) {
        article.toggleArchiveWithSync(
            context: context, apiClient: apiClient,
            isAuthenticated: isAuthenticated, showToast: showToastMessage
        )
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
                    article.status = .processing
                } catch {
                    FolioLogger.sync.error("retryArticle failed: \(error) — \(article.url)")
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

        // Apply category filter at predicate level for correct pagination
        if let categoryID = selectedCategory?.id {
            descriptor.predicate = #Predicate<Article> { article in
                article.category?.id == categoryID
            }
        }

        descriptor.fetchLimit = pageSize
        descriptor.fetchOffset = currentPage * pageSize

        guard var fetched = try? context.fetch(descriptor) else {
            FolioLogger.data.error("vm-debug: loadPage fetch failed")
            isLoading = false
            return
        }
        FolioLogger.data.info("vm-debug: loadPage reset=\(reset), fetched=\(fetched.count), offset=\(self.currentPage * self.pageSize)")

        // Tag filtering must remain post-fetch because SwiftData #Predicate
        // does not support relationship collection queries.
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
