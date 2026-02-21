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
            mergeServerArticles(response.data)
        } catch {
            syncError = error.localizedDescription
        }

        fetchArticles()
        isLoading = false
    }

    // MARK: - Merge Server Articles

    private func mergeServerArticles(_ dtos: [ArticleDTO]) {
        let articleRepo = ArticleRepository(context: context)
        let tagRepo = TagRepository(context: context)
        let categoryRepo = CategoryRepository(context: context)

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
        }

        try? context.save()
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

        for article in articles {
            let key: String
            if calendar.isDateInToday(article.createdAt) {
                key = String(localized: "today", defaultValue: "Today")
            } else if calendar.isDateInYesterday(article.createdAt) {
                key = String(localized: "yesterday", defaultValue: "Yesterday")
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                key = formatter.string(from: article.createdAt)
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
