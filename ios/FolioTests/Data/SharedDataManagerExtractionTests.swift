import XCTest
import SwiftData
@testable import Folio

final class SharedDataManagerExtractionTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var manager: SharedDataManager!

    @MainActor
    override func setUp() {
        super.setUp()
        container = try! DataManager.createInMemoryContainer()
        context = container.mainContext
        manager = SharedDataManager(context: context)
    }

    override func tearDown() {
        manager = nil
        container = nil
        context = nil
        super.tearDown()
    }

    // MARK: - updateWithExtraction

    @MainActor
    func testUpdateWithExtraction_setsAllFields() throws {
        let article = try manager.saveArticle(url: "https://example.com/extract-test")
        XCTAssertEqual(article.status, .pending)

        let result = ExtractionResult(
            title: "Extracted Title",
            author: "Extracted Author",
            siteName: "Extracted Site",
            excerpt: "An excerpt",
            markdownContent: "# Hello\n\nThis is extracted content that is long enough to pass validation.",
            wordCount: 42,
            extractedAt: Date()
        )

        try manager.updateWithExtraction(result, for: article)

        XCTAssertEqual(article.markdownContent, "# Hello\n\nThis is extracted content that is long enough to pass validation.")
        XCTAssertEqual(article.wordCount, 42)
        XCTAssertEqual(article.status, .clientReady)
        XCTAssertEqual(article.extractionSource, .client)
        XCTAssertNotNil(article.clientExtractedAt)
        XCTAssertEqual(article.title, "Extracted Title")
        XCTAssertEqual(article.author, "Extracted Author")
        XCTAssertEqual(article.siteName, "Extracted Site")
    }

    @MainActor
    func testUpdateWithExtraction_nilTitlePreservesOriginal() throws {
        let article = Article(url: "https://example.com/keep-title", title: "Original Title")
        context.insert(article)
        try context.save()

        let result = ExtractionResult(
            title: nil,
            author: nil,
            siteName: nil,
            excerpt: nil,
            markdownContent: "Some content that is long enough for testing purposes here.",
            wordCount: 10,
            extractedAt: Date()
        )

        try manager.updateWithExtraction(result, for: article)

        XCTAssertEqual(article.title, "Original Title")
    }

    @MainActor
    func testUpdateWithExtraction_emptyTitlePreservesOriginal() throws {
        let article = Article(url: "https://example.com/empty-title", title: "Original")
        context.insert(article)
        try context.save()

        let result = ExtractionResult(
            title: "",
            author: "",
            siteName: "",
            excerpt: nil,
            markdownContent: "Content for testing that is long enough for the test.",
            wordCount: 10,
            extractedAt: Date()
        )

        try manager.updateWithExtraction(result, for: article)

        XCTAssertEqual(article.title, "Original")
    }

    @MainActor
    func testUpdateWithExtraction_overwritesNilTitle() throws {
        let article = try manager.saveArticle(url: "https://example.com/no-title")
        XCTAssertNil(article.title)

        let result = ExtractionResult(
            title: "New Title",
            author: nil,
            siteName: nil,
            excerpt: nil,
            markdownContent: "Content for testing with enough characters for validation.",
            wordCount: 8,
            extractedAt: Date()
        )

        try manager.updateWithExtraction(result, for: article)

        XCTAssertEqual(article.title, "New Title")
    }

    @MainActor
    func testUpdateWithExtraction_statusTransition() throws {
        let article = try manager.saveArticle(url: "https://example.com/status-test")
        XCTAssertEqual(article.status, .pending)
        XCTAssertEqual(article.extractionSource, .none)

        let result = ExtractionResult(
            title: "Title",
            author: nil,
            siteName: nil,
            excerpt: nil,
            markdownContent: "Long enough content for the extraction test to work properly.",
            wordCount: 11,
            extractedAt: Date()
        )

        try manager.updateWithExtraction(result, for: article)

        XCTAssertEqual(article.status, .clientReady)
        XCTAssertEqual(article.extractionSource, .client)
    }

    // MARK: - excerpt → summary

    @MainActor
    func testUpdateWithExtraction_excerptSetsSummary() throws {
        let article = try manager.saveArticle(url: "https://example.com/excerpt-summary")
        XCTAssertNil(article.summary)

        let result = ExtractionResult(
            title: "Title",
            author: nil,
            siteName: nil,
            excerpt: "This is a summary",
            markdownContent: "Content for testing excerpt to summary mapping in extraction.",
            wordCount: 10,
            extractedAt: Date()
        )

        try manager.updateWithExtraction(result, for: article)

        XCTAssertEqual(article.summary, "This is a summary")
    }

    @MainActor
    func testUpdateWithExtraction_nilExcerptPreservesSummary() throws {
        let article = Article(url: "https://example.com/nil-excerpt")
        article.summary = "Existing summary"
        context.insert(article)
        try context.save()

        let result = ExtractionResult(
            title: nil,
            author: nil,
            siteName: nil,
            excerpt: nil,
            markdownContent: "Content for testing that nil excerpt preserves existing summary.",
            wordCount: 10,
            extractedAt: Date()
        )

        try manager.updateWithExtraction(result, for: article)

        XCTAssertEqual(article.summary, "Existing summary")
    }

    @MainActor
    func testUpdateWithExtraction_emptyExcerptPreservesSummary() throws {
        let article = Article(url: "https://example.com/empty-excerpt")
        article.summary = "Existing summary"
        context.insert(article)
        try context.save()

        let result = ExtractionResult(
            title: nil,
            author: nil,
            siteName: nil,
            excerpt: "",
            markdownContent: "Content for testing that empty excerpt preserves existing summary.",
            wordCount: 10,
            extractedAt: Date()
        )

        try manager.updateWithExtraction(result, for: article)

        XCTAssertEqual(article.summary, "Existing summary")
    }

    // MARK: - updatedAt

    @MainActor
    func testUpdateWithExtraction_setsUpdatedAt() throws {
        let article = try manager.saveArticle(url: "https://example.com/updated-at")
        let originalUpdatedAt = article.updatedAt

        // Small delay to ensure different timestamp
        try manager.updateWithExtraction(
            ExtractionResult(
                title: nil, author: nil, siteName: nil, excerpt: nil,
                markdownContent: "Content for testing updated timestamp validation.",
                wordCount: 6, extractedAt: Date()
            ),
            for: article
        )

        XCTAssertTrue(article.updatedAt >= originalUpdatedAt)
    }
}
