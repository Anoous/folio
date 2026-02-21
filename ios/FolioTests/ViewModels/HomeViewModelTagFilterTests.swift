import XCTest
import SwiftData
@testable import Folio

final class HomeViewModelTagFilterTests: XCTestCase {

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
    func testFilterBySingleTag() throws {
        let tagRepo = TagRepository(context: context)
        let swiftTag = try tagRepo.findOrCreate(name: "Swift")

        let a1 = Article(url: "https://example.com/swift", title: "Swift article")
        a1.tags = [swiftTag]
        let a2 = Article(url: "https://example.com/other", title: "Other article")
        context.insert(a1)
        context.insert(a2)
        try context.save()

        let vm = HomeViewModel(context: context)
        vm.selectedTags = [swiftTag]
        vm.fetchArticles()
        XCTAssertEqual(vm.articles.count, 1)
        XCTAssertEqual(vm.articles.first?.title, "Swift article")
    }

    @MainActor
    func testFilterByMultipleTags_AND() throws {
        let tagRepo = TagRepository(context: context)
        let swift = try tagRepo.findOrCreate(name: "Swift")
        let ios = try tagRepo.findOrCreate(name: "iOS")

        let a1 = Article(url: "https://example.com/both", title: "Both tags")
        a1.tags = [swift, ios]
        let a2 = Article(url: "https://example.com/swift-only", title: "Swift only")
        a2.tags = [swift]
        context.insert(a1)
        context.insert(a2)
        try context.save()

        let vm = HomeViewModel(context: context)
        vm.selectedTags = [swift, ios]
        vm.fetchArticles()
        XCTAssertEqual(vm.articles.count, 1)
        XCTAssertEqual(vm.articles.first?.title, "Both tags")
    }

    @MainActor
    func testDeselectTag_removesFilter() throws {
        let tagRepo = TagRepository(context: context)
        let swift = try tagRepo.findOrCreate(name: "Swift")

        let a1 = Article(url: "https://example.com/1", title: "Article 1")
        a1.tags = [swift]
        let a2 = Article(url: "https://example.com/2", title: "Article 2")
        context.insert(a1)
        context.insert(a2)
        try context.save()

        let vm = HomeViewModel(context: context)
        vm.selectedTags = [swift]
        vm.fetchArticles()
        XCTAssertEqual(vm.articles.count, 1)

        vm.selectedTags = []
        vm.fetchArticles()
        XCTAssertEqual(vm.articles.count, 2)
    }

    @MainActor
    func testCombineCategoryAndTagFilter() throws {
        let catRepo = CategoryRepository(context: context)
        let tech = try catRepo.fetchBySlug("tech")!
        let tagRepo = TagRepository(context: context)
        let swift = try tagRepo.findOrCreate(name: "Swift")

        let a1 = Article(url: "https://example.com/tech-swift", title: "Tech Swift")
        a1.category = tech
        a1.tags = [swift]
        let a2 = Article(url: "https://example.com/tech-only", title: "Tech only")
        a2.category = tech
        let a3 = Article(url: "https://example.com/swift-only", title: "Swift only")
        a3.tags = [swift]
        context.insert(a1)
        context.insert(a2)
        context.insert(a3)
        try context.save()

        let vm = HomeViewModel(context: context)
        vm.selectedCategory = tech
        vm.selectedTags = [swift]
        vm.fetchArticles()
        XCTAssertEqual(vm.articles.count, 1)
        XCTAssertEqual(vm.articles.first?.title, "Tech Swift")
    }

    @MainActor
    func testPopularTags_orderedByCount() throws {
        let tagRepo = TagRepository(context: context)
        let t1 = try tagRepo.findOrCreate(name: "A")
        t1.articleCount = 10
        let t2 = try tagRepo.findOrCreate(name: "B")
        t2.articleCount = 5
        let t3 = try tagRepo.findOrCreate(name: "C")
        t3.articleCount = 20
        try context.save()

        let popular = try tagRepo.fetchPopular(limit: 3)
        XCTAssertEqual(popular.first?.name, "C")
    }
}
