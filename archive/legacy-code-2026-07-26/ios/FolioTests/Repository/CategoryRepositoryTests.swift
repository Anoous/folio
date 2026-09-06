import XCTest
import SwiftData
@testable import Folio

final class CategoryRepositoryTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var repo: CategoryRepository!

    @MainActor
    override func setUp() {
        super.setUp()
        container = try! DataManager.createInMemoryContainer()
        context = container.mainContext
        repo = CategoryRepository(context: context)
    }

    override func tearDown() {
        repo = nil
        context = nil
        container = nil
        super.tearDown()
    }

    @MainActor
    func testFetchAll_returns9DefaultCategories() throws {
        let categories = try repo.fetchAll()
        XCTAssertEqual(categories.count, 9)
    }

    @MainActor
    func testFetchBySlug_found() throws {
        let tech = try repo.fetchBySlug("tech")
        XCTAssertNotNil(tech)
        XCTAssertEqual(tech?.slug, "tech")
        XCTAssertEqual(tech?.icon, "cpu")
    }
}
