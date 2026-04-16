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

    func index(_ article: Article) {
        do {
            try searchManager.indexArticle(article)
        } catch {
            FolioLogger.data.error("search index insert failed for \(article.id): \(error.localizedDescription)")
        }
    }

    func update(_ article: Article) {
        do {
            try searchManager.updateIndex(article)
        } catch {
            FolioLogger.data.error("search index update failed for \(article.id): \(error.localizedDescription)")
        }
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
