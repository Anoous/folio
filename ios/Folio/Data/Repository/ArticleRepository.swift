import Foundation
import SwiftData

final class ArticleRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// Create a pending article from a URL
    func save(url: String, tags: [String] = [], note: String? = nil) throws -> Article {
        let sourceType = SourceType.detect(from: url)
        let article = Article(url: url, sourceType: sourceType)
        context.insert(article)

        if !tags.isEmpty {
            let tagRepo = TagRepository(context: context)
            for tagName in tags {
                let tag = try tagRepo.findOrCreate(name: tagName, isAIGenerated: false)
                article.tags.append(tag)
            }
        }

        try context.save()
        return article
    }

    /// Paginated fetch with optional filtering
    func fetchAll(
        category: Folio.Category? = nil,
        tags: [Tag] = [],
        sortBy: SortOrder = .reverse,
        limit: Int = 20,
        offset: Int = 0
    ) throws -> [Article] {
        var descriptor = FetchDescriptor<Article>(
            sortBy: [SortDescriptor(\.createdAt, order: sortBy)]
        )
        descriptor.fetchLimit = limit
        descriptor.fetchOffset = offset

        var articles = try context.fetch(descriptor)

        if let category {
            articles = articles.filter { $0.category?.id == category.id }
        }

        if !tags.isEmpty {
            let tagIDs = Set(tags.map(\.id))
            articles = articles.filter { article in
                !Set(article.tags.map(\.id)).isDisjoint(with: tagIDs)
            }
        }

        return articles
    }

    /// Fetch article by ID
    func fetchByID(_ id: UUID) throws -> Article? {
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    /// Update article (saves context)
    func update(_ article: Article) throws {
        article.updatedAt = Date()
        try context.save()
    }

    /// Delete article
    func delete(_ article: Article) throws {
        context.delete(article)
        try context.save()
    }

    /// Fetch all pending articles
    func fetchPending() throws -> [Article] {
        let pendingRaw = ArticleStatus.pending.rawValue
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate { $0.statusRaw == pendingRaw },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return try context.fetch(descriptor)
    }

    /// Fetch article by server ID
    func fetchByServerID(_ serverID: String) throws -> Article? {
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate { $0.serverID == serverID }
        )
        return try context.fetch(descriptor).first
    }

    /// Fetch article by URL
    func fetchByURL(_ url: String) throws -> Article? {
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate { $0.url == url }
        )
        return try context.fetch(descriptor).first
    }

    /// Check if a URL already exists
    func existsByURL(_ url: String) throws -> Bool {
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate { $0.url == url }
        )
        return try context.fetchCount(descriptor) > 0
    }

    /// Update article processing status
    func updateStatus(_ article: Article, status: ArticleStatus) throws {
        article.status = status
        article.updatedAt = Date()
        try context.save()
    }

    /// Count articles saved in the current calendar month
    func countForCurrentMonth() throws -> Int {
        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate { $0.createdAt >= startOfMonth }
        )
        return try context.fetchCount(descriptor)
    }
}
