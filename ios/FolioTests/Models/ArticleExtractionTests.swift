import XCTest
import SwiftData
@testable import Folio

final class ArticleExtractionTests: XCTestCase {

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

    // MARK: - ExtractionSource enum

    func testExtractionSource_rawValues() {
        XCTAssertEqual(ExtractionSource.none.rawValue, "none")
        XCTAssertEqual(ExtractionSource.client.rawValue, "client")
        XCTAssertEqual(ExtractionSource.server.rawValue, "server")
    }

    func testExtractionSource_initFromRawValue() {
        XCTAssertEqual(ExtractionSource(rawValue: "none"), ExtractionSource.none)
        XCTAssertEqual(ExtractionSource(rawValue: "client"), ExtractionSource.client)
        XCTAssertEqual(ExtractionSource(rawValue: "server"), ExtractionSource.server)
        XCTAssertNil(ExtractionSource(rawValue: "unknown"))
    }

    // MARK: - ArticleStatus.clientReady

    func testClientReady_rawValue() {
        XCTAssertEqual(ArticleStatus.clientReady.rawValue, "clientReady")
    }

    func testClientReady_initFromRawValue() {
        XCTAssertEqual(ArticleStatus(rawValue: "clientReady"), .clientReady)
    }

    // MARK: - Article extraction properties

    @MainActor
    func testArticle_defaultExtractionSource() {
        let article = Article(url: "https://example.com")
        context.insert(article)
        XCTAssertEqual(article.extractionSource, .none)
        XCTAssertEqual(article.extractionSourceRaw, "none")
        XCTAssertNil(article.clientExtractedAt)
    }

    @MainActor
    func testArticle_setExtractionSource() {
        let article = Article(url: "https://example.com")
        context.insert(article)

        article.extractionSource = .client
        XCTAssertEqual(article.extractionSourceRaw, "client")
        XCTAssertEqual(article.extractionSource, .client)

        article.extractionSource = .server
        XCTAssertEqual(article.extractionSourceRaw, "server")
        XCTAssertEqual(article.extractionSource, .server)
    }

    @MainActor
    func testArticle_clientExtractedAt() {
        let article = Article(url: "https://example.com")
        context.insert(article)

        let now = Date()
        article.clientExtractedAt = now
        XCTAssertEqual(article.clientExtractedAt, now)
    }

    @MainActor
    func testArticle_invalidExtractionSourceRaw_defaultsToNone() {
        let article = Article(url: "https://example.com")
        context.insert(article)
        article.extractionSourceRaw = "invalid"
        XCTAssertEqual(article.extractionSource, .none)
    }

    // MARK: - SourceType.supportsClientExtraction

    func testSupportsClientExtraction_webTrue() {
        XCTAssertTrue(SourceType.web.supportsClientExtraction)
    }

    func testSupportsClientExtraction_wechatTrue() {
        XCTAssertTrue(SourceType.wechat.supportsClientExtraction)
    }

    func testSupportsClientExtraction_twitterTrue() {
        XCTAssertTrue(SourceType.twitter.supportsClientExtraction)
    }

    func testSupportsClientExtraction_weiboTrue() {
        XCTAssertTrue(SourceType.weibo.supportsClientExtraction)
    }

    func testSupportsClientExtraction_zhihuTrue() {
        XCTAssertTrue(SourceType.zhihu.supportsClientExtraction)
    }

    func testSupportsClientExtraction_newsletterTrue() {
        XCTAssertTrue(SourceType.newsletter.supportsClientExtraction)
    }

    func testSupportsClientExtraction_youtubeFalse() {
        XCTAssertFalse(SourceType.youtube.supportsClientExtraction)
    }

    // MARK: - ArticleStatus Codable round-trip with clientReady

    func testArticleStatus_codableRoundTrip_clientReady() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(ArticleStatus.clientReady)
        let decoded = try decoder.decode(ArticleStatus.self, from: data)
        XCTAssertEqual(decoded, .clientReady)
    }
}
