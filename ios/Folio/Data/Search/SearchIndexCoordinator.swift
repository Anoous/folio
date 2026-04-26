import Foundation
import SwiftData

@MainActor
final class SearchIndexCoordinator {
    static let shared: SearchIndexCoordinator = {
        do {
            return SearchIndexCoordinator(searchManager: try FTS5SearchManager(inMemory: false))
        } catch {
            fatalError("Failed to create search index coordinator: \(error)")
        }
    }()

    let searchManager: FTS5SearchManager

    init(searchManager: FTS5SearchManager) {
        self.searchManager = searchManager
    }

    func sync(_ article: Article) {
        do {
            try searchManager.upsertArticle(article)
        } catch {
            FolioLogger.data.error("search index sync failed for \(article.id): \(error.localizedDescription)")
        }
    }

    func index(_ article: Article) {
        sync(article)
    }

    func update(_ article: Article) {
        sync(article)
    }

    func remove(articleID: UUID) {
        do {
            try searchManager.removeFromIndex(articleID: articleID)
        } catch {
            FolioLogger.data.error("search index delete failed for \(articleID): \(error.localizedDescription)")
        }
    }

    func rebuild(context: ModelContext) {
        let articleRepository = ArticleRepository(context: context)
        do {
            let articles = try articleRepository.fetchAllForIndex()
            try searchManager.rebuildAll(articles: articles)
            FolioLogger.data.info("search index rebuilt from coordinator: \(articles.count) articles")
        } catch {
            FolioLogger.data.error("search index rebuild failed: \(error.localizedDescription)")
        }
    }
}
