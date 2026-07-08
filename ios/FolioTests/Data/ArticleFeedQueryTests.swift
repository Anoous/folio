import XCTest
import SwiftData
@testable import Folio

final class ArticleFeedQueryTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    @MainActor
    override func setUp() {
        super.setUp()
        container = try! DataManager.createInMemoryContainer()
        context = container.mainContext
    }

    override func tearDown() {
        context = nil
        container = nil
        super.tearDown()
    }

    @MainActor
    func testSelectedTagsUseAllTagsSemanticsForHomeFeed() throws {
        let tagRepo = TagRepository(context: context)
        let swift = try tagRepo.findOrCreate(name: "Swift")
        let ios = try tagRepo.findOrCreate(name: "iOS")

        let both = Article(url: "https://example.com/both", title: "Both")
        both.tags = [swift, ios]
        both.createdAt = Date(timeIntervalSince1970: 2)
        let swiftOnly = Article(url: "https://example.com/swift", title: "Swift")
        swiftOnly.tags = [swift]
        swiftOnly.createdAt = Date(timeIntervalSince1970: 1)
        context.insert(both)
        context.insert(swiftOnly)
        try context.save()

        let query = ArticleFeedQuery(context: context, pageSize: 20)
        let page = try query.reset(filter: .init(tags: [swift, ios]))

        XCTAssertEqual(page.articles.map(\.displayTitle), ["Both"])
        XCTAssertFalse(page.hasMore)
    }

    @MainActor
    func testPaginationKeepsDatabaseOffsetWhenTagFilterSkipsRows() throws {
        let tagRepo = TagRepository(context: context)
        let selected = try tagRepo.findOrCreate(name: "Selected")
        for i in 0..<8 {
            let article = Article(url: "https://example.com/\(i)", title: "Article \(i)")
            article.createdAt = Date(timeIntervalSince1970: Double(100 - i))
            if [0, 4, 7].contains(i) {
                article.tags = [selected]
            }
            context.insert(article)
        }
        try context.save()

        let query = ArticleFeedQuery(context: context, pageSize: 2)
        let first = try query.reset(filter: .init(tags: [selected]))
        let second = try query.next()

        XCTAssertEqual(first.articles.map(\.displayTitle), ["Article 0", "Article 4"])
        XCTAssertEqual(second.articles.map(\.displayTitle), ["Article 7"])
        XCTAssertFalse(second.hasMore)
    }

    @MainActor
    func testPaginationRetainsExtraTagMatchesFromCurrentBatch() throws {
        let tagRepo = TagRepository(context: context)
        let selected = try tagRepo.findOrCreate(name: "Selected")
        for i in 0..<6 {
            let article = Article(url: "https://example.com/overflow-\(i)", title: "Article \(i)")
            article.createdAt = Date(timeIntervalSince1970: Double(100 - i))
            if i < 3 {
                article.tags = [selected]
            }
            context.insert(article)
        }
        try context.save()

        let query = ArticleFeedQuery(context: context, pageSize: 2)
        let first = try query.reset(filter: .init(tags: [selected]))
        let second = try query.next()

        XCTAssertEqual(first.articles.map(\.displayTitle), ["Article 0", "Article 1"])
        XCTAssertEqual(second.articles.map(\.displayTitle), ["Article 2"])
        XCTAssertFalse(second.hasMore)
    }
}
