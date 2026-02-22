import XCTest
import SwiftData
@testable import Folio

final class HomeViewModelTests: XCTestCase {

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
    func testFetchArticles_returnsAllWhenNoFilter() throws {
        MockDataFactory.populateSampleData(context: context)
        let vm = HomeViewModel(context: context)
        vm.fetchArticles()
        XCTAssertEqual(vm.articles.count, 20) // page size = 20
    }

    @MainActor
    func testFetchArticles_sortedByDateDescending() throws {
        let a1 = Article(url: "https://example.com/1", title: "Old")
        a1.createdAt = Date(timeIntervalSince1970: 1000)
        let a2 = Article(url: "https://example.com/2", title: "New")
        a2.createdAt = Date(timeIntervalSince1970: 2000)
        context.insert(a1)
        context.insert(a2)
        try context.save()

        let vm = HomeViewModel(context: context)
        vm.fetchArticles()
        XCTAssertEqual(vm.articles.first?.title, "New")
        XCTAssertEqual(vm.articles.last?.title, "Old")
    }

    @MainActor
    func testGroupByDate_today() throws {
        let a = Article(url: "https://example.com/today", title: "Today article")
        a.createdAt = Date()
        context.insert(a)
        try context.save()

        let vm = HomeViewModel(context: context)
        let grouped = vm.groupByDate([a])
        XCTAssertEqual(grouped.first?.0, "Today")
    }

    @MainActor
    func testGroupByDate_yesterday() throws {
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date()))!
        let a = Article(url: "https://example.com/yesterday", title: "Yesterday article")
        a.createdAt = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: yesterday)!
        context.insert(a)
        try context.save()

        let vm = HomeViewModel(context: context)
        let grouped = vm.groupByDate([a])
        XCTAssertEqual(grouped.first?.0, "Yesterday")
    }

    @MainActor
    func testGroupByDate_specificDate() throws {
        let a = Article(url: "https://example.com/old", title: "Old article")
        a.createdAt = Date(timeIntervalSinceNow: -30 * 86400)
        context.insert(a)
        try context.save()

        let vm = HomeViewModel(context: context)
        let grouped = vm.groupByDate([a])
        XCTAssertNotEqual(grouped.first?.0, "Today")
        XCTAssertNotEqual(grouped.first?.0, "Yesterday")
    }

    @MainActor
    func testPagination_loadsNextPage() throws {
        // Create 25 articles
        for i in 0..<25 {
            let a = Article(url: "https://example.com/\(i)", title: "Article \(i)")
            a.createdAt = Date(timeIntervalSinceNow: Double(-i) * 3600)
            context.insert(a)
        }
        try context.save()

        let vm = HomeViewModel(context: context)
        vm.fetchArticles()
        XCTAssertEqual(vm.articles.count, 20)

        vm.loadNextPage()
        XCTAssertEqual(vm.articles.count, 25)
    }

    @MainActor
    func testMarkAsRead() throws {
        let a = Article(url: "https://example.com/read", title: "Read me")
        context.insert(a)
        try context.save()
        XCTAssertEqual(a.readProgress, 0)

        let vm = HomeViewModel(context: context)
        vm.markAsRead(a)
        XCTAssertGreaterThan(a.readProgress, 0)
        XCTAssertNotNil(a.lastReadAt)
    }

    // MARK: - Action Method Tests

    @MainActor
    func testToggleFavorite_togglesIsFavorite() throws {
        let a = Article(url: "https://example.com/fav", title: "Fav")
        context.insert(a)
        try context.save()
        XCTAssertFalse(a.isFavorite)

        let vm = HomeViewModel(context: context)
        vm.toggleFavorite(a)
        XCTAssertTrue(a.isFavorite)

        vm.toggleFavorite(a)
        XCTAssertFalse(a.isFavorite)
    }

    @MainActor
    func testToggleFavorite_setsToast() throws {
        let a = Article(url: "https://example.com/fav-toast", title: "Fav Toast")
        context.insert(a)
        try context.save()

        let vm = HomeViewModel(context: context)
        vm.toggleFavorite(a)
        XCTAssertTrue(vm.showToast)
        XCTAssertFalse(vm.toastMessage.isEmpty)
    }

    @MainActor
    func testArchiveArticle_togglesIsArchived() throws {
        let a = Article(url: "https://example.com/archive", title: "Archive")
        context.insert(a)
        try context.save()
        XCTAssertFalse(a.isArchived)

        let vm = HomeViewModel(context: context)
        vm.archiveArticle(a)
        XCTAssertTrue(a.isArchived)

        vm.archiveArticle(a)
        XCTAssertFalse(a.isArchived)
    }

    @MainActor
    func testArchiveArticle_setsToast() throws {
        let a = Article(url: "https://example.com/archive-toast", title: "Archive Toast")
        context.insert(a)
        try context.save()

        let vm = HomeViewModel(context: context)
        vm.archiveArticle(a)
        XCTAssertTrue(vm.showToast)
        XCTAssertFalse(vm.toastMessage.isEmpty)
    }

    @MainActor
    func testDeleteArticle_removesFromContext() throws {
        let a = Article(url: "https://example.com/delete", title: "Delete me")
        context.insert(a)
        try context.save()
        let id = a.id

        let vm = HomeViewModel(context: context)
        vm.deleteArticle(a)

        let descriptor = FetchDescriptor<Article>(predicate: #Predicate { $0.id == id })
        let found = try context.fetch(descriptor)
        XCTAssertTrue(found.isEmpty)
    }

    @MainActor
    func testDeleteArticle_setsToast() throws {
        let a = Article(url: "https://example.com/delete-toast", title: "Delete Toast")
        context.insert(a)
        try context.save()

        let vm = HomeViewModel(context: context)
        vm.deleteArticle(a)
        XCTAssertTrue(vm.showToast)
        XCTAssertFalse(vm.toastMessage.isEmpty)
    }

    @MainActor
    func testFetchArticles_emptyDatabase() throws {
        let vm = HomeViewModel(context: context)
        vm.fetchArticles()
        XCTAssertTrue(vm.articles.isEmpty)
    }

    @MainActor
    func testLoadNextPage_noMorePages() throws {
        // Create fewer than page size (20) articles
        for i in 0..<5 {
            let a = Article(url: "https://example.com/small-\(i)", title: "Small \(i)")
            a.createdAt = Date(timeIntervalSinceNow: Double(-i) * 3600)
            context.insert(a)
        }
        try context.save()

        let vm = HomeViewModel(context: context)
        vm.fetchArticles()
        XCTAssertEqual(vm.articles.count, 5)

        // loadNextPage should be a no-op since hasMorePages is false
        vm.loadNextPage()
        XCTAssertEqual(vm.articles.count, 5)
    }

    @MainActor
    func testMarkAsRead_alreadyRead() throws {
        let a = Article(url: "https://example.com/already-read", title: "Already Read")
        a.readProgress = 0.5
        context.insert(a)
        try context.save()

        let vm = HomeViewModel(context: context)
        vm.markAsRead(a)
        // Should NOT reset readProgress to 0.01 since it's already > 0
        XCTAssertEqual(a.readProgress, 0.5)
    }
}
