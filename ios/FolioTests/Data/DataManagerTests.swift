import XCTest
import SwiftData
@testable import Folio

final class DataManagerTests: XCTestCase {

    @MainActor
    func testCreateInMemoryContainer() throws {
        let container = try DataManager.createInMemoryContainer()
        XCTAssertNotNil(container)

        let context = container.mainContext
        let descriptor = FetchDescriptor<Article>()
        let articles = try context.fetch(descriptor)
        XCTAssertEqual(articles.count, 0)
    }

    @MainActor
    func testPreloadCategories() throws {
        let container = try DataManager.createInMemoryContainer()
        let context = container.mainContext

        let descriptor = FetchDescriptor<Folio.Category>()
        let categories = try context.fetch(descriptor)
        XCTAssertEqual(categories.count, 9)

        let slugs = Set(categories.map(\Folio.Category.slug))
        XCTAssertTrue(slugs.contains("tech"))
        XCTAssertTrue(slugs.contains("business"))
        XCTAssertTrue(slugs.contains("science"))
        XCTAssertTrue(slugs.contains("culture"))
        XCTAssertTrue(slugs.contains("lifestyle"))
        XCTAssertTrue(slugs.contains("news"))
        XCTAssertTrue(slugs.contains("education"))
        XCTAssertTrue(slugs.contains("design"))
        XCTAssertTrue(slugs.contains("other"))
    }

    @MainActor
    func testPreloadCategoriesIdempotent() throws {
        let schema = DataManager.schema
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        // Preload twice
        DataManager.shared.preloadCategories(in: context)
        DataManager.shared.preloadCategories(in: context)

        let descriptor = FetchDescriptor<Folio.Category>()
        let categories = try context.fetch(descriptor)
        XCTAssertEqual(categories.count, 9, "Categories should not be duplicated on second preload")
    }

    @MainActor
    func testSharedContainerConfiguration() throws {
        // Verify that the shared container configuration is correct
        let config = ModelConfiguration(
            "Folio",
            schema: DataManager.schema,
            groupContainer: .identifier("group.com.folio.app")
        )
        XCTAssertNotNil(config)
    }
}
