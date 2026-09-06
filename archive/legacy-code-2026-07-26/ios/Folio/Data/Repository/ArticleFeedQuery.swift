import Foundation
import SwiftData

@MainActor
final class ArticleFeedQuery {
    struct Filter {
        var category: Folio.Category?
        var tags: [Tag]

        init(category: Folio.Category? = nil, tags: [Tag] = []) {
            self.category = category
            self.tags = tags
        }
    }

    struct Page {
        let articles: [Article]
        let hasMore: Bool
    }

    private let context: ModelContext
    private let pageSize: Int
    private var currentFilter = Filter()
    private var nextFetchOffset = 0
    private var exhausted = false
    private var bufferedArticles: [Article] = []

    init(context: ModelContext, pageSize: Int = 20) {
        self.context = context
        self.pageSize = max(1, pageSize)
    }

    func reset(filter: Filter = Filter()) throws -> Page {
        currentFilter = filter
        nextFetchOffset = 0
        exhausted = false
        bufferedArticles = []
        return try loadNextPage()
    }

    func next() throws -> Page {
        guard !exhausted || !bufferedArticles.isEmpty else {
            return Page(articles: [], hasMore: false)
        }
        return try loadNextPage()
    }

    private func loadNextPage() throws -> Page {
        let needsTagFilter = !currentFilter.tags.isEmpty
        let selectedTagIDs = needsTagFilter ? Set(currentFilter.tags.map(\.id)) : []
        let batchSize = needsTagFilter ? pageSize * 3 : pageSize
        var collected = takeBufferedArticles()
        var fetchOffset = nextFetchOffset

        repeat {
            if collected.count >= pageSize { break }

            var descriptor = FetchDescriptor<Article>(
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )

            if let categoryID = currentFilter.category?.id {
                descriptor.predicate = #Predicate<Article> { article in
                    article.category?.id == categoryID
                }
            }

            descriptor.fetchLimit = batchSize
            descriptor.fetchOffset = fetchOffset

            let batch = try context.fetch(descriptor)
            if batch.count < batchSize {
                exhausted = true
            }
            fetchOffset += batch.count

            if needsTagFilter {
                collected.append(contentsOf: batch.filter { article in
                    selectedTagIDs.isSubset(of: Set(article.tags.map(\.id)))
                })
            } else {
                collected.append(contentsOf: batch)
            }
        } while needsTagFilter && collected.count < pageSize && !exhausted

        nextFetchOffset = fetchOffset
        let pageArticles = Array(collected.prefix(pageSize))
        bufferedArticles.append(contentsOf: collected.dropFirst(pageSize))
        return Page(articles: pageArticles, hasMore: !bufferedArticles.isEmpty || !exhausted)
    }

    private func takeBufferedArticles() -> [Article] {
        guard !bufferedArticles.isEmpty else { return [] }
        let articles = Array(bufferedArticles.prefix(pageSize))
        bufferedArticles.removeFirst(min(pageSize, bufferedArticles.count))
        return articles
    }
}
