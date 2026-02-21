import XCTest
import SwiftData
@testable import Folio

final class ArticleModelTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    @MainActor
    override func setUp() {
        super.setUp()
        let schema = Schema([Article.self, Tag.self, Category.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(for: schema, configurations: [config])
        context = container.mainContext
    }

    override func tearDown() {
        container = nil
        context = nil
        super.tearDown()
    }

    @MainActor
    func testArticleCreation() {
        let article = Article(url: "https://example.com/test")
        context.insert(article)

        XCTAssertNotNil(article.id)
        XCTAssertEqual(article.url, "https://example.com/test")
        XCTAssertNil(article.title)
        XCTAssertEqual(article.status, .pending)
        XCTAssertEqual(article.isFavorite, false)
        XCTAssertEqual(article.isArchived, false)
        XCTAssertEqual(article.readProgress, 0)
        XCTAssertEqual(article.syncState, .pendingUpload)
        XCTAssertEqual(article.sourceType, .web)
        XCTAssertTrue(article.keyPoints.isEmpty)
        XCTAssertTrue(article.tags.isEmpty)
        XCTAssertNil(article.category)
    }

    func testSourceTypeDetection_wechat() {
        XCTAssertEqual(SourceType.detect(from: "https://mp.weixin.qq.com/s/abc123"), .wechat)
    }

    func testSourceTypeDetection_twitter() {
        XCTAssertEqual(SourceType.detect(from: "https://twitter.com/user/status/123"), .twitter)
        XCTAssertEqual(SourceType.detect(from: "https://x.com/user/status/123"), .twitter)
    }

    func testSourceTypeDetection_weibo() {
        XCTAssertEqual(SourceType.detect(from: "https://weibo.com/123456"), .weibo)
    }

    func testSourceTypeDetection_zhihu() {
        XCTAssertEqual(SourceType.detect(from: "https://www.zhihu.com/question/123"), .zhihu)
    }

    func testSourceTypeDetection_web() {
        XCTAssertEqual(SourceType.detect(from: "https://example.com/article"), .web)
    }

    @MainActor
    func testArticleTagRelationship() {
        let article = Article(url: "https://example.com")
        let tag1 = Tag(name: "Swift")
        let tag2 = Tag(name: "iOS")

        context.insert(article)
        context.insert(tag1)
        context.insert(tag2)

        article.tags = [tag1, tag2]

        XCTAssertEqual(article.tags.count, 2)
        XCTAssertTrue(article.tags.contains(where: { $0.name == "Swift" }))
        XCTAssertTrue(article.tags.contains(where: { $0.name == "iOS" }))
    }

    @MainActor
    func testArticleCategoryRelationship() {
        let article = Article(url: "https://example.com")
        let category = Category(slug: "tech", nameZH: "技术", nameEN: "Technology", icon: "cpu")

        context.insert(article)
        context.insert(category)

        article.category = category

        XCTAssertNotNil(article.category)
        XCTAssertEqual(article.category?.slug, "tech")
    }

    func testArticleStatusEnum() {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for status in [ArticleStatus.pending, .processing, .ready, .failed] {
            let data = try! encoder.encode(status)
            let decoded = try! decoder.decode(ArticleStatus.self, from: data)
            XCTAssertEqual(status, decoded)
        }
    }
}
