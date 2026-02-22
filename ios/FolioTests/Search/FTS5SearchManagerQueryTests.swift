import XCTest
@testable import Folio

final class FTS5SearchManagerQueryTests: XCTestCase {

    private var manager: FTS5SearchManager!

    override func setUp() {
        super.setUp()
        manager = try! FTS5SearchManager(inMemory: true)
    }

    override func tearDown() {
        manager = nil
        super.tearDown()
    }

    func testSearch_findsMatchingArticle() throws {
        let article = Article(url: "https://example.com", title: "Swift Programming Guide")
        article.markdownContent = "Learn Swift programming language basics"
        try manager.indexArticle(article)

        let results = try manager.search(query: "Swift")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.articleID, article.id)
    }

    func testSearch_BM25Ranking() throws {
        // Article with keyword in title should rank higher
        let titleMatch = Article(url: "https://example.com/1", title: "Machine Learning Guide")
        titleMatch.markdownContent = "This is about programming"
        try manager.indexArticle(titleMatch)

        let contentMatch = Article(url: "https://example.com/2", title: "Programming Guide")
        contentMatch.markdownContent = "Machine learning is a subset of AI"
        try manager.indexArticle(contentMatch)

        let results = try manager.search(query: "Machine Learning")
        XCTAssertGreaterThanOrEqual(results.count, 1)
        // Title match should rank higher (lower bm25 score is better)
        if results.count >= 2 {
            XCTAssertEqual(results.first?.articleID, titleMatch.id)
        }
    }

    func testSearch_prefixMatch() throws {
        let article = Article(url: "https://example.com", title: "Learning Swift")
        try manager.indexArticle(article)

        let results = try manager.search(query: "learn")
        XCTAssertEqual(results.count, 1, "Prefix 'learn' should match 'Learning'")
    }

    func testSearch_chineseText() throws {
        let article = Article(url: "https://example.com", title: "深度学习入门")
        article.markdownContent = "机器学习是人工智能的核心技术"
        try manager.indexArticle(article)

        let results = try manager.search(query: "机器学习")
        XCTAssertGreaterThanOrEqual(results.count, 1, "Chinese search should find matching content")
    }

    func testSearch_noResults() throws {
        let article = Article(url: "https://example.com", title: "Swift Guide")
        try manager.indexArticle(article)

        let results = try manager.search(query: "Python")
        XCTAssertEqual(results.count, 0)
    }

    func testSearchWithHighlight() throws {
        let article = Article(url: "https://example.com", title: "Swift Programming")
        try manager.indexArticle(article)

        let results = try manager.searchWithHighlight(query: "Swift")
        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results.first?.highlightedTitle?.contains("<mark>") ?? false)
    }

    func testSearchWithSnippet() throws {
        let article = Article(url: "https://example.com", title: "Guide")
        article.markdownContent = "This is a long article about Swift programming with many details about concurrency and async await patterns"
        try manager.indexArticle(article)

        let results = try manager.searchWithSnippet(query: "Swift")
        XCTAssertEqual(results.count, 1)
        XCTAssertNotNil(results.first?.snippet)
    }

    func testSearch_limitResults() throws {
        for i in 0..<10 {
            let article = Article(url: "https://example.com/\(i)", title: "Swift Article \(i)")
            try manager.indexArticle(article)
        }

        let results = try manager.search(query: "Swift", limit: 3)
        XCTAssertEqual(results.count, 3)
    }

    func testSearch_caseInsensitive() throws {
        let article = Article(url: "https://example.com", title: "SWIFT PROGRAMMING")
        try manager.indexArticle(article)

        let results = try manager.search(query: "swift")
        XCTAssertEqual(results.count, 1)
    }

    // MARK: - Edge Cases

    func testSearch_whitespaceOnlyQuery() throws {
        let article = Article(url: "https://example.com", title: "Swift")
        try manager.indexArticle(article)

        let results = try manager.search(query: "   ")
        XCTAssertEqual(results.count, 0)
    }

    func testSearch_specialCharacters() throws {
        let article = Article(url: "https://example.com", title: "Swift Guide")
        try manager.indexArticle(article)

        // Special characters should not crash — they may throw FTS5 errors which is fine
        do {
            _ = try manager.search(query: "\"")
        } catch {
            // FTS5 error is acceptable for malformed query
        }
        do {
            _ = try manager.search(query: "(")
        } catch {
            // FTS5 error is acceptable for malformed query
        }
    }

    func testSearch_limitZero() throws {
        let article = Article(url: "https://example.com", title: "Swift")
        try manager.indexArticle(article)

        let results = try manager.search(query: "Swift", limit: 0)
        XCTAssertEqual(results.count, 0)
    }

    func testSearchWithSnippet_noResults() throws {
        let results = try manager.searchWithSnippet(query: "nonexistent")
        XCTAssertEqual(results.count, 0)
    }
}
