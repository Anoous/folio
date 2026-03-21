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

    // MARK: - SourceType.detect Gaps

    func testSourceType_youtube() {
        XCTAssertEqual(SourceType.detect(from: "https://www.youtube.com/watch?v=abc"), .youtube)
    }

    func testSourceType_youtubeShort() {
        XCTAssertEqual(SourceType.detect(from: "https://youtu.be/abc"), .youtube)
    }

    func testSourceType_weiboCN() {
        XCTAssertEqual(SourceType.detect(from: "https://m.weibo.cn/detail/123"), .weibo)
    }

    func testSourceType_invalidURL() {
        XCTAssertEqual(SourceType.detect(from: "not a url"), .web)
    }

    func testSourceType_emptyString() {
        XCTAssertEqual(SourceType.detect(from: ""), .web)
    }

    func testSyncState_allCases() {
        XCTAssertEqual(SyncState.pendingUpload.rawValue, "pendingUpload")
        XCTAssertEqual(SyncState.synced.rawValue, "synced")
        XCTAssertEqual(SyncState.pendingUpdate.rawValue, "pendingUpdate")
        XCTAssertEqual(SyncState.conflict.rawValue, "conflict")
    }

    // MARK: - Article.countWords

    func testCountWords_englishText() {
        XCTAssertEqual(Article.countWords("Hello world"), 2)
        XCTAssertEqual(Article.countWords("one two three four five"), 5)
    }

    func testCountWords_chineseText() {
        // Each CJK character counts as one word
        XCTAssertEqual(Article.countWords("你好世界"), 4)
        XCTAssertEqual(Article.countWords("测试"), 2)
    }

    func testCountWords_mixedCJKAndEnglish() {
        // "Hello" = 1 word, "世界" = 2 CJK characters
        XCTAssertEqual(Article.countWords("Hello 世界"), 3)
    }

    func testCountWords_empty() {
        XCTAssertEqual(Article.countWords(""), 0)
    }

    func testCountWords_whitespaceOnly() {
        XCTAssertEqual(Article.countWords("   \n\t  "), 0)
    }

    func testCountWords_singleWord() {
        XCTAssertEqual(Article.countWords("hello"), 1)
    }

    func testCountWords_multipleSpaces() {
        XCTAssertEqual(Article.countWords("hello   world"), 2)
    }

    // MARK: - Manual Article Convenience Init

    @MainActor
    func testManualArticle_wordCountUsesCountWords() {
        let content = "This is a test sentence with seven words"
        let article = Article(content: content)
        context.insert(article)

        // countWords should give 8, not content.count (40)
        XCTAssertEqual(article.wordCount, Article.countWords(content))
        XCTAssertEqual(article.wordCount, 8)
    }

    @MainActor
    func testManualArticle_wordCountCJK() {
        let content = "这是一段中文测试内容"
        let article = Article(content: content)
        context.insert(article)

        // Each CJK character = 1 word, 10 characters = 10 words
        XCTAssertEqual(article.wordCount, 10)
        XCTAssertEqual(article.wordCount, Article.countWords(content))
    }

    @MainActor
    func testManualArticle_wordCountMixed() {
        // 150 chars of English prose but far fewer words
        let content = "Swift is a powerful and intuitive programming language for Apple platforms"
        let article = Article(content: content)
        context.insert(article)

        // 11 words, NOT 73 characters
        XCTAssertEqual(article.wordCount, 11)
        XCTAssertNotEqual(article.wordCount, content.count)
    }

    @MainActor
    func testManualArticle_sourceTypeIsManual() {
        let article = Article(content: "test")
        context.insert(article)
        XCTAssertEqual(article.sourceType, .manual)
        XCTAssertNil(article.url)
    }

    @MainActor
    func testManualArticle_contentStored() {
        let content = "My thought about Swift"
        let article = Article(content: content)
        context.insert(article)
        XCTAssertEqual(article.markdownContent, content)
    }
}
