import XCTest
import SwiftData
@testable import Folio

final class SharedDataManagerTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var manager: SharedDataManager!

    @MainActor
    override func setUp() {
        super.setUp()
        container = try! DataManager.createInMemoryContainer()
        context = container.mainContext
        manager = SharedDataManager(context: context)
    }

    override func tearDown() {
        manager = nil
        container = nil
        context = nil
        super.tearDown()
    }

    @MainActor
    func testSaveArticle_createsPendingArticle() throws {
        let article = try manager.saveArticle(url: "https://example.com/test")
        XCTAssertEqual(article.url, "https://example.com/test")
        XCTAssertEqual(article.status, .pending)
    }

    @MainActor
    func testSaveArticle_extractsURLFromPlainText() throws {
        let article = try manager.saveArticleFromText("Check this out: https://example.com/link some text")
        XCTAssertEqual(article.url, "https://example.com/link")
    }

    @MainActor
    func testSaveArticle_duplicateURL() throws {
        _ = try manager.saveArticle(url: "https://example.com/dup")
        XCTAssertThrowsError(try manager.saveArticle(url: "https://example.com/dup")) { error in
            XCTAssertTrue(error is SharedDataError)
        }
    }

    @MainActor
    func testSaveArticle_setsSourceType() throws {
        let article = try manager.saveArticle(url: "https://mp.weixin.qq.com/s/abc123")
        XCTAssertEqual(article.sourceType, .wechat)
    }

    @MainActor
    func testSharedContainer_accessible() throws {
        let article = try manager.saveArticle(url: "https://example.com/shared")
        let exists = try manager.existsByURL("https://example.com/shared")
        XCTAssertTrue(exists)
        XCTAssertNotNil(article.id)
    }
}
