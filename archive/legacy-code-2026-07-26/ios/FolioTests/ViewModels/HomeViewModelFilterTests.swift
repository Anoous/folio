import XCTest
import SwiftData
@testable import Folio

final class HomeViewModelFilterTests: XCTestCase {

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
    func testFilterByCategory_tech() throws {
        let catRepo = CategoryRepository(context: context)
        let tech = try catRepo.fetchBySlug("tech")!
        tech.articleCount = 1

        let a1 = Article(url: "https://example.com/tech", title: "Tech article")
        a1.category = tech
        let a2 = Article(url: "https://example.com/other", title: "Other article")
        context.insert(a1)
        context.insert(a2)
        try context.save()

        let vm = HomeViewModel(context: context)
        vm.selectedCategory = tech
        vm.fetchArticles()
        XCTAssertEqual(vm.articles.count, 1)
        XCTAssertEqual(vm.articles.first?.title, "Tech article")
    }

    @MainActor
    func testFilterByCategory_all() throws {
        let a1 = Article(url: "https://example.com/1", title: "Article 1")
        let a2 = Article(url: "https://example.com/2", title: "Article 2")
        context.insert(a1)
        context.insert(a2)
        try context.save()

        let vm = HomeViewModel(context: context)
        vm.selectedCategory = nil
        vm.fetchArticles()
        XCTAssertEqual(vm.articles.count, 2)
    }

    @MainActor
    func testFilterByCategory_emptyCategory() throws {
        let catRepo = CategoryRepository(context: context)
        let design = try catRepo.fetchBySlug("design")!

        let a1 = Article(url: "https://example.com/1", title: "No category match")
        context.insert(a1)
        try context.save()

        let vm = HomeViewModel(context: context)
        vm.selectedCategory = design
        vm.fetchArticles()
        XCTAssertEqual(vm.articles.count, 0)
    }

    @MainActor
    func testCategoriesWithArticles() throws {
        let catRepo = CategoryRepository(context: context)
        let allCats = try catRepo.fetchAll()
        let catsWithArticles = allCats.filter { $0.articleCount > 0 }
        XCTAssertEqual(catsWithArticles.count, 0, "Initially no categories have articles")

        let tech = try catRepo.fetchBySlug("tech")!
        tech.articleCount = 5
        try context.save()

        let updatedCats = try catRepo.fetchAll()
        let withArticles = updatedCats.filter { $0.articleCount > 0 }
        XCTAssertEqual(withArticles.count, 1)
    }

    @MainActor
    func testCategoryFilterResetsPagination() throws {
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

        // Changing category resets pagination
        let catRepo = CategoryRepository(context: context)
        vm.selectedCategory = try catRepo.fetchBySlug("tech")
        vm.fetchArticles()
        XCTAssertEqual(vm.articles.count, 0, "After switching to tech category with no articles")
    }
}
