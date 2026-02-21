import XCTest
import SwiftData
@testable import Folio

final class ReaderViewModelTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    @MainActor
    override func setUp() {
        super.setUp()
        container = try! DataManager.createInMemoryContainer()
        context = container.mainContext
    }

    override func tearDown() {
        container = nil
        context = nil
        super.tearDown()
    }

    @MainActor
    func testLoadArticle_setsProperties() throws {
        let article = Article(url: "https://example.com", title: "Test Title")
        article.summary = "Test summary"
        article.markdownContent = "Test content"
        context.insert(article)
        try context.save()

        let vm = ReaderViewModel(article: article, context: context)
        XCTAssertEqual(vm.article.title, "Test Title")
        XCTAssertEqual(vm.article.summary, "Test summary")
        XCTAssertEqual(vm.article.markdownContent, "Test content")
    }

    @MainActor
    func testLoadArticle_marksAsRead() throws {
        let article = Article(url: "https://example.com", title: "Read me")
        XCTAssertEqual(article.readProgress, 0)
        context.insert(article)
        try context.save()

        let vm = ReaderViewModel(article: article, context: context)
        vm.markAsRead()
        XCTAssertGreaterThan(article.readProgress, 0)
        XCTAssertNotNil(article.lastReadAt)
    }

    @MainActor
    func testMetaInfo_wordCount() throws {
        let article = Article(url: "https://example.com", title: "Test")
        article.markdownContent = String(repeating: "word ", count: 100) // ~100 words
        context.insert(article)

        let vm = ReaderViewModel(article: article, context: context)
        XCTAssertGreaterThan(vm.wordCount, 0)
    }

    @MainActor
    func testMetaInfo_estimatedReadTime() throws {
        let article = Article(url: "https://example.com", title: "Test")
        article.markdownContent = String(repeating: "字", count: 800) // ~2 min at 400 char/min
        context.insert(article)

        let vm = ReaderViewModel(article: article, context: context)
        XCTAssertEqual(vm.estimatedReadTimeMinutes, 2)
    }

    @MainActor
    func testDeleteArticle() throws {
        let article = Article(url: "https://example.com/delete", title: "Delete me")
        context.insert(article)
        try context.save()
        let id = article.id

        let vm = ReaderViewModel(article: article, context: context)
        vm.deleteArticle()

        let descriptor = FetchDescriptor<Article>(predicate: #Predicate { $0.id == id })
        let found = try context.fetch(descriptor)
        XCTAssertTrue(found.isEmpty)
    }

    @MainActor
    func testToggleFavorite() throws {
        let article = Article(url: "https://example.com", title: "Fav")
        context.insert(article)
        try context.save()
        XCTAssertFalse(article.isFavorite)

        let vm = ReaderViewModel(article: article, context: context)
        vm.toggleFavorite()
        XCTAssertTrue(article.isFavorite)

        vm.toggleFavorite()
        XCTAssertFalse(article.isFavorite)
    }

    @MainActor
    func testCopyMarkdown() throws {
        let article = Article(url: "https://example.com", title: "Copy")
        article.markdownContent = "# Hello World"
        context.insert(article)

        let vm = ReaderViewModel(article: article, context: context)
        vm.copyMarkdown()
        XCTAssertEqual(UIPasteboard.general.string, "# Hello World")
    }
}
