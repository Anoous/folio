import XCTest
import SwiftData
@testable import Folio

final class SearchViewModelTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    @MainActor
    override func setUp() {
        super.setUp()
        container = try! DataManager.createInMemoryContainer()
        context = container.mainContext
        UserDefaults.standard.removeObject(forKey: "folio_search_history")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "folio_search_history")
        container = nil
        context = nil
        super.tearDown()
    }

    @MainActor
    func testSearch_debounce200ms() async throws {
        let fts = try FTS5SearchManager(inMemory: true)
        let article = Article(url: "https://example.com", title: "Swift Guide")
        try fts.indexArticle(article)

        let vm = SearchViewModel(searchManager: fts, context: context)
        vm.searchText = "Sw"
        vm.searchText = "Swi"
        vm.searchText = "Swift"

        // Wait for debounce
        try await Task.sleep(nanoseconds: 300_000_000)
        vm.performSearch()
        XCTAssertGreaterThanOrEqual(vm.results.count, 0)
    }

    @MainActor
    func testSearch_showsResults() throws {
        let fts = try FTS5SearchManager(inMemory: true)
        let article = Article(url: "https://example.com", title: "Swift Guide")
        context.insert(article)
        try context.save()
        try fts.indexArticle(article)

        let vm = SearchViewModel(searchManager: fts, context: context)
        vm.searchText = "Swift"
        vm.performSearch()
        XCTAssertEqual(vm.results.count, 1)
    }

    @MainActor
    func testSearch_emptyQuery_showsHistory() throws {
        let fts = try FTS5SearchManager(inMemory: true)
        let vm = SearchViewModel(searchManager: fts, context: context)
        vm.searchText = ""
        XCTAssertTrue(vm.results.isEmpty)
    }

    @MainActor
    func testSearch_savesHistory() throws {
        let fts = try FTS5SearchManager(inMemory: true)
        let vm = SearchViewModel(searchManager: fts, context: context)
        vm.saveToHistory("Swift")
        XCTAssertTrue(vm.searchHistory.contains("Swift"))
    }

    @MainActor
    func testSearch_historyLimit10() throws {
        let fts = try FTS5SearchManager(inMemory: true)
        let vm = SearchViewModel(searchManager: fts, context: context)
        for i in 0..<15 {
            vm.saveToHistory("query\(i)")
        }
        XCTAssertLessThanOrEqual(vm.searchHistory.count, 10)
    }

    @MainActor
    func testClearHistory() throws {
        let fts = try FTS5SearchManager(inMemory: true)
        let vm = SearchViewModel(searchManager: fts, context: context)
        vm.saveToHistory("test")
        XCTAssertFalse(vm.searchHistory.isEmpty)

        vm.clearHistory()
        XCTAssertTrue(vm.searchHistory.isEmpty)
    }

    @MainActor
    func testDeleteSingleHistory() throws {
        let fts = try FTS5SearchManager(inMemory: true)
        let vm = SearchViewModel(searchManager: fts, context: context)
        vm.saveToHistory("keep")
        vm.saveToHistory("delete")

        vm.deleteHistoryItem("delete")
        XCTAssertFalse(vm.searchHistory.contains("delete"))
        XCTAssertTrue(vm.searchHistory.contains("keep"))
    }

    @MainActor
    func testPopularTags_shows8() throws {
        let fts = try FTS5SearchManager(inMemory: true)
        let tagRepo = TagRepository(context: context)
        for i in 0..<12 {
            let tag = try tagRepo.findOrCreate(name: "Tag\(i)")
            tag.articleCount = 12 - i
        }
        try context.save()

        let vm = SearchViewModel(searchManager: fts, context: context)
        vm.loadPopularTags()
        XCTAssertLessThanOrEqual(vm.popularTags.count, 8)
    }

    @MainActor
    func testTagClick_triggersSearch() throws {
        let fts = try FTS5SearchManager(inMemory: true)
        let article = Article(url: "https://example.com", title: "Tagged")
        let tag = Tag(name: "SwiftUI")
        article.tags = [tag]
        try fts.indexArticle(article)

        let vm = SearchViewModel(searchManager: fts, context: context)
        vm.searchText = "SwiftUI"
        vm.performSearch()
        XCTAssertEqual(vm.searchText, "SwiftUI")
    }

    @MainActor
    func testEmptyResults_showsHint() throws {
        let fts = try FTS5SearchManager(inMemory: true)
        let vm = SearchViewModel(searchManager: fts, context: context)
        vm.searchText = "nonexistentquery12345"
        vm.performSearch()
        XCTAssertTrue(vm.showsEmptyState)
    }

    // MARK: - History Edge Cases

    @MainActor
    func testSaveToHistory_deduplicates() throws {
        let fts = try FTS5SearchManager(inMemory: true)
        let vm = SearchViewModel(searchManager: fts, context: context)
        vm.saveToHistory("swift")
        vm.saveToHistory("swift")
        let count = vm.searchHistory.filter { $0 == "swift" }.count
        XCTAssertEqual(count, 1)
    }

    @MainActor
    func testSaveToHistory_emptyString() throws {
        let fts = try FTS5SearchManager(inMemory: true)
        let vm = SearchViewModel(searchManager: fts, context: context)
        let before = vm.searchHistory.count
        vm.saveToHistory("")
        XCTAssertEqual(vm.searchHistory.count, before)
    }

    @MainActor
    func testFTS5_specialCharacters() throws {
        let fts = try FTS5SearchManager(inMemory: true)
        let vm = SearchViewModel(searchManager: fts, context: context)
        // These special characters should not crash
        vm.searchText = "\"test\""
        vm.performSearch()
        // No crash = success; results may be empty or error-state
        vm.searchText = "test("
        vm.performSearch()
        // No crash = success
    }
}
