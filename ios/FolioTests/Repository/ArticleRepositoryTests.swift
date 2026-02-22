import XCTest
import SwiftData
@testable import Folio

final class ArticleRepositoryTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var repo: ArticleRepository!

    @MainActor
    override func setUp() {
        super.setUp()
        container = try! DataManager.createInMemoryContainer()
        context = container.mainContext
        repo = ArticleRepository(context: context)
    }

    override func tearDown() {
        repo = nil
        context = nil
        container = nil
        super.tearDown()
    }

    @MainActor
    func testSave_createsArticleWithPendingStatus() throws {
        let article = try repo.save(url: "https://example.com/article")
        XCTAssertEqual(article.url, "https://example.com/article")
        XCTAssertEqual(article.status, .pending)
        XCTAssertEqual(article.sourceType, .web)
    }

    @MainActor
    func testFetchAll_returnsSortedByDate() throws {
        let a1 = try repo.save(url: "https://example.com/1")
        a1.createdAt = Date(timeIntervalSince1970: 1000)
        let a2 = try repo.save(url: "https://example.com/2")
        a2.createdAt = Date(timeIntervalSince1970: 2000)
        try context.save()

        // Reverse sort (newest first)
        let results = try repo.fetchAll(sortBy: .reverse)
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results.first?.url, "https://example.com/2")
    }

    @MainActor
    func testFetchAll_filterByCategory() throws {
        let catRepo = CategoryRepository(context: context)
        let techCat = try catRepo.fetchBySlug("tech")!

        let a1 = try repo.save(url: "https://example.com/tech")
        a1.category = techCat
        _ = try repo.save(url: "https://example.com/other")
        try context.save()

        let results = try repo.fetchAll(category: techCat, limit: 100)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.url, "https://example.com/tech")
    }

    @MainActor
    func testFetchAll_filterByTags() throws {
        let tagRepo = TagRepository(context: context)
        let swiftTag = try tagRepo.findOrCreate(name: "Swift")

        let a1 = try repo.save(url: "https://example.com/swift")
        a1.tags.append(swiftTag)
        _ = try repo.save(url: "https://example.com/other")
        try context.save()

        let results = try repo.fetchAll(tags: [swiftTag], limit: 100)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.url, "https://example.com/swift")
    }

    @MainActor
    func testFetchAll_pagination() throws {
        for i in 0..<5 {
            _ = try repo.save(url: "https://example.com/\(i)")
        }

        let page1 = try repo.fetchAll(limit: 2, offset: 0)
        XCTAssertEqual(page1.count, 2)

        let page2 = try repo.fetchAll(limit: 2, offset: 2)
        XCTAssertEqual(page2.count, 2)

        let page3 = try repo.fetchAll(limit: 2, offset: 4)
        XCTAssertEqual(page3.count, 1)
    }

    @MainActor
    func testFetchByID_found() throws {
        let article = try repo.save(url: "https://example.com")
        let found = try repo.fetchByID(article.id)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.url, "https://example.com")
    }

    @MainActor
    func testFetchByID_notFound() throws {
        let found = try repo.fetchByID(UUID())
        XCTAssertNil(found)
    }

    @MainActor
    func testExistsByURL_exists() throws {
        _ = try repo.save(url: "https://example.com/exists")
        XCTAssertTrue(try repo.existsByURL("https://example.com/exists"))
    }

    @MainActor
    func testExistsByURL_notExists() throws {
        XCTAssertFalse(try repo.existsByURL("https://example.com/nope"))
    }

    @MainActor
    func testDelete_removesArticle() throws {
        let article = try repo.save(url: "https://example.com/delete-me")
        let id = article.id
        try repo.delete(article)
        let found = try repo.fetchByID(id)
        XCTAssertNil(found)
    }

    @MainActor
    func testFetchPending_returnsOnlyPending() throws {
        let a1 = try repo.save(url: "https://example.com/pending")
        let a2 = try repo.save(url: "https://example.com/completed")
        a2.status = .ready
        try context.save()

        let pending = try repo.fetchPending()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.id, a1.id)
    }

    @MainActor
    func testUpdateStatus() throws {
        let article = try repo.save(url: "https://example.com")
        try repo.updateStatus(article, status: .ready)
        XCTAssertEqual(article.status, .ready)
    }

    @MainActor
    func testCountForCurrentMonth() throws {
        _ = try repo.save(url: "https://example.com/this-month")

        // Create an old article (last year)
        let oldArticle = Article(url: "https://example.com/old")
        oldArticle.createdAt = Calendar.current.date(byAdding: .year, value: -1, to: Date())!
        context.insert(oldArticle)
        try context.save()

        let count = try repo.countForCurrentMonth()
        XCTAssertEqual(count, 1)
    }

    // MARK: - fetchAll Multi-Tag Filter (OR Semantics)

    @MainActor
    func testFetchAll_multipleTagFilter_orSemantics() throws {
        let tagRepo = TagRepository(context: context)
        let swiftTag = try tagRepo.findOrCreate(name: "Swift")
        let iosTag = try tagRepo.findOrCreate(name: "iOS")

        let a1 = try repo.save(url: "https://example.com/swift-only")
        a1.tags.append(swiftTag)
        let a2 = try repo.save(url: "https://example.com/ios-only")
        a2.tags.append(iosTag)
        _ = try repo.save(url: "https://example.com/no-tags")
        try context.save()

        // OR semantics: any article with Swift or iOS tag
        let results = try repo.fetchAll(tags: [swiftTag, iosTag], limit: 100)
        XCTAssertEqual(results.count, 2)
    }

    // MARK: - fetchByURL

    @MainActor
    func testFetchByURL_found() throws {
        _ = try repo.save(url: "https://example.com/findme")
        let found = try repo.fetchByURL("https://example.com/findme")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.url, "https://example.com/findme")
    }

    @MainActor
    func testFetchByURL_notFound() throws {
        let found = try repo.fetchByURL("https://example.com/nonexistent")
        XCTAssertNil(found)
    }

    // MARK: - Save with Tags

    @MainActor
    func testSave_withTags() throws {
        let article = try repo.save(url: "https://example.com/tagged", tags: ["Swift", "iOS"])
        XCTAssertEqual(article.tags.count, 2)
        XCTAssertTrue(article.tags.contains(where: { $0.name == "Swift" }))
        XCTAssertTrue(article.tags.contains(where: { $0.name == "iOS" }))
    }

    // MARK: - Update Sets Timestamp

    @MainActor
    func testUpdate_setsTimestamp() throws {
        let article = try repo.save(url: "https://example.com/update-ts")
        let originalUpdatedAt = article.updatedAt

        // Small delay to ensure timestamp changes
        Thread.sleep(forTimeInterval: 0.01)

        try repo.update(article)
        XCTAssertGreaterThan(article.updatedAt, originalUpdatedAt)
    }
}
