import XCTest
import SwiftData
@testable import Folio

final class TagRepositoryTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var repo: TagRepository!

    @MainActor
    override func setUp() {
        super.setUp()
        container = try! DataManager.createInMemoryContainer()
        context = container.mainContext
        repo = TagRepository(context: context)
    }

    override func tearDown() {
        repo = nil
        context = nil
        container = nil
        super.tearDown()
    }

    @MainActor
    func testFindOrCreate_createsNew() throws {
        let tag = try repo.findOrCreate(name: "Swift", isAIGenerated: false)
        XCTAssertEqual(tag.name, "Swift")
        XCTAssertFalse(tag.isAIGenerated)

        let all = try repo.fetchAll()
        XCTAssertTrue(all.contains(where: { $0.name == "Swift" }))
    }

    @MainActor
    func testFindOrCreate_findsExisting() throws {
        let tag1 = try repo.findOrCreate(name: "iOS")
        let tag2 = try repo.findOrCreate(name: "iOS")
        XCTAssertEqual(tag1.id, tag2.id)
    }

    @MainActor
    func testFetchPopular_orderedByCount() throws {
        let t1 = try repo.findOrCreate(name: "A")
        t1.articleCount = 10
        let t2 = try repo.findOrCreate(name: "B")
        t2.articleCount = 5
        let t3 = try repo.findOrCreate(name: "C")
        t3.articleCount = 20
        try context.save()

        let popular = try repo.fetchPopular(limit: 3)
        XCTAssertEqual(popular.first?.name, "C")
        XCTAssertEqual(popular.last?.name, "B")
    }

    @MainActor
    func testDelete_removesTag() throws {
        let tag = try repo.findOrCreate(name: "Temp")
        try repo.delete(tag)

        let all = try repo.fetchAll()
        XCTAssertFalse(all.contains(where: { $0.name == "Temp" }))
    }
}
