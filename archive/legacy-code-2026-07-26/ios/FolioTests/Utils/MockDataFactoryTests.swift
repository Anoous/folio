import XCTest
import SwiftData
@testable import Folio

final class MockDataFactoryTests: XCTestCase {

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

    func testGenerateArticles_correctCount() {
        let articles = MockDataFactory.generateArticles(count: 10)
        XCTAssertEqual(articles.count, 10)
    }

    func testGenerateArticles_diverseSourceTypes() {
        let articles = MockDataFactory.generateArticles(count: 30)
        let sourceTypes = Set(articles.map(\.sourceType))
        XCTAssertGreaterThanOrEqual(sourceTypes.count, 3,
            "Expected at least 3 different source types, got \(sourceTypes)")
    }

    func testGenerateArticles_diverseStatuses() {
        let articles = MockDataFactory.generateArticles(count: 30)
        let statuses = Set(articles.map(\.status))
        XCTAssertGreaterThanOrEqual(statuses.count, 2,
            "Expected at least 2 different statuses, got \(statuses)")
    }

    func testGenerateTags_notEmpty() {
        let tags = MockDataFactory.generateTags()
        XCTAssertGreaterThanOrEqual(tags.count, 15)
        XCTAssertLessThanOrEqual(tags.count, 20)
    }

    @MainActor
    func testPopulateSampleData() throws {
        MockDataFactory.populateSampleData(context: context)

        let descriptor = FetchDescriptor<Article>()
        let articles = try context.fetch(descriptor)
        XCTAssertEqual(articles.count, 30)
    }
}
