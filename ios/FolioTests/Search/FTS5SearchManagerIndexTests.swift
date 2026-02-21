import XCTest
@testable import Folio

final class FTS5SearchManagerIndexTests: XCTestCase {

    private var manager: FTS5SearchManager!

    override func setUp() {
        super.setUp()
        manager = try! FTS5SearchManager(inMemory: true)
    }

    override func tearDown() {
        manager = nil
        super.tearDown()
    }

    func testCreateFTS5Table() {
        // Table is created during init; verify by checking row count
        XCTAssertEqual(try manager.rowCount(), 0)
    }

    func testIndexArticle_addsToIndex() throws {
        let article = Article(url: "https://example.com", title: "Swift Concurrency")
        article.markdownContent = "Learn about async await in Swift"
        article.summary = "A guide to Swift concurrency"

        try manager.indexArticle(article)
        XCTAssertEqual(try manager.rowCount(), 1)
    }

    func testRemoveFromIndex() throws {
        let article = Article(url: "https://example.com", title: "Remove me")
        try manager.indexArticle(article)
        XCTAssertEqual(try manager.rowCount(), 1)

        try manager.removeFromIndex(articleID: article.id)
        XCTAssertEqual(try manager.rowCount(), 0)
    }

    func testUpdateIndex() throws {
        let article = Article(url: "https://example.com", title: "Original Title")
        try manager.indexArticle(article)

        article.title = "Updated Title"
        try manager.updateIndex(article)

        let results = try manager.search(query: "Updated")
        XCTAssertEqual(results.count, 1)

        let oldResults = try manager.search(query: "Original")
        XCTAssertEqual(oldResults.count, 0)
    }

    func testRebuildAll() throws {
        let articles = (0..<5).map { i in
            Article(url: "https://example.com/\(i)", title: "Article \(i)")
        }
        try manager.rebuildAll(articles: articles)
        XCTAssertEqual(try manager.rowCount(), 5)
    }

    func testIndexArticle_allFieldsIndexed() throws {
        let article = Article(url: "https://example.com", title: "Unique Title")
        article.markdownContent = "Unique content text here"
        article.summary = "Unique summary text"
        article.author = "UniqueAuthor"
        article.siteName = "UniqueSite"
        let tag = Tag(name: "UniqueTag")
        article.tags = [tag]

        try manager.indexArticle(article)

        // Search each field
        XCTAssertEqual(try manager.search(query: "Unique Title").count, 1)
        XCTAssertEqual(try manager.search(query: "Unique content").count, 1)
        XCTAssertEqual(try manager.search(query: "Unique summary").count, 1)
        XCTAssertEqual(try manager.search(query: "UniqueTag").count, 1)
        XCTAssertEqual(try manager.search(query: "UniqueAuthor").count, 1)
        XCTAssertEqual(try manager.search(query: "UniqueSite").count, 1)
    }
}
