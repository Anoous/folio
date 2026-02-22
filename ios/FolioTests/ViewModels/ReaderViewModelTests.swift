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

    // MARK: - Archive Tests

    @MainActor
    func testArchiveArticle_togglesIsArchived() throws {
        let article = Article(url: "https://example.com/archive", title: "Archive")
        context.insert(article)
        try context.save()
        XCTAssertFalse(article.isArchived)

        let vm = ReaderViewModel(article: article, context: context)
        vm.archiveArticle()
        XCTAssertTrue(article.isArchived)

        vm.archiveArticle()
        XCTAssertFalse(article.isArchived)
    }

    @MainActor
    func testArchiveArticle_setsToast() throws {
        let article = Article(url: "https://example.com/archive-toast", title: "Archive Toast")
        context.insert(article)
        try context.save()

        let vm = ReaderViewModel(article: article, context: context)
        vm.archiveArticle()
        XCTAssertTrue(vm.showToast)
        XCTAssertFalse(vm.toastMessage.isEmpty)
    }

    // MARK: - Copy & Share Edge Cases

    @MainActor
    func testCopyMarkdown_nilContent_showsErrorToast() throws {
        let article = Article(url: "https://example.com/no-content", title: "No Content")
        // markdownContent is nil by default
        context.insert(article)

        let vm = ReaderViewModel(article: article, context: context)
        vm.copyMarkdown()
        XCTAssertTrue(vm.showToast)
        XCTAssertTrue(vm.toastMessage.contains("No content"))
    }

    @MainActor
    func testShareURL_returnsValidURL() throws {
        let article = Article(url: "https://example.com/valid", title: "Valid")
        context.insert(article)

        let vm = ReaderViewModel(article: article, context: context)
        let url = vm.shareURL()
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.absoluteString, "https://example.com/valid")
    }

    @MainActor
    func testShareURL_invalidURL_returnsNil() throws {
        let article = Article(url: "", title: "Invalid")
        context.insert(article)

        let vm = ReaderViewModel(article: article, context: context)
        let url = vm.shareURL()
        XCTAssertNil(url)
    }

    // MARK: - Word Count Edge Cases

    @MainActor
    func testWordCount_nilContent() throws {
        let article = Article(url: "https://example.com/nil-content", title: "Nil")
        // markdownContent is nil
        context.insert(article)

        let vm = ReaderViewModel(article: article, context: context)
        XCTAssertEqual(vm.wordCount, 0)
        XCTAssertEqual(vm.estimatedReadTimeMinutes, 1)
    }

    @MainActor
    func testEstimatedReadTime_shortContent() throws {
        let article = Article(url: "https://example.com/short", title: "Short")
        article.markdownContent = "Hello" // < 400 chars
        context.insert(article)

        let vm = ReaderViewModel(article: article, context: context)
        XCTAssertEqual(vm.estimatedReadTimeMinutes, 1)
    }
}
