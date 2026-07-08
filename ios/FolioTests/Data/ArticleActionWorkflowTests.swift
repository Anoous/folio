import XCTest
import SwiftData
@testable import Folio

final class ArticleActionWorkflowTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    @MainActor
    override func setUp() {
        super.setUp()
        container = try! DataManager.createInMemoryContainer()
        context = container.mainContext
    }

    override func tearDown() {
        context = nil
        container = nil
        super.tearDown()
    }

    @MainActor
    func testToggleFavoriteMarksSyncedArticleForPendingUpdate() throws {
        let article = Article(url: "https://example.com/fav")
        article.serverID = "server-1"
        article.syncState = .synced
        context.insert(article)
        try context.save()

        let workflow = ArticleActionWorkflow(context: context)
        var toast: (String, String?)?
        workflow.toggleFavorite(article, isAuthenticated: false) { message, icon in
            toast = (message, icon)
        }

        XCTAssertTrue(article.isFavorite)
        XCTAssertEqual(article.syncState, .pendingUpdate)
        XCTAssertTrue(article.dirtyFields.contains(.favorite))
        XCTAssertNotNil(article.favoriteUpdatedAt)
        XCTAssertNotNil(toast)
    }

    @MainActor
    func testDeleteArticleOwnsPendingDeletionAndIndexRemoval() throws {
        let searchIndexer = SearchIndexCoordinator(searchManager: try FTS5SearchManager(inMemory: true))
        let article = Article(url: "https://example.com/delete", title: "Delete Me")
        article.serverID = "server-delete"
        context.insert(article)
        try context.save()
        searchIndexer.sync(article)
        XCTAssertEqual(try searchIndexer.searchManager.search(query: "Delete").count, 1)

        let workflow = ArticleActionWorkflow(context: context, searchIndexCoordinator: searchIndexer)
        workflow.delete(article)

        XCTAssertEqual(try context.fetch(FetchDescriptor<Article>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PendingDeletion>()).first?.serverID, "server-delete")
        XCTAssertEqual(try context.fetch(FetchDescriptor<DeletionRecord>()).first?.serverID, "server-delete")
        XCTAssertEqual(try searchIndexer.searchManager.search(query: "Delete").count, 0)
    }
}
