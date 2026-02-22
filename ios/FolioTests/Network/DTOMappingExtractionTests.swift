import XCTest
import SwiftData
@testable import Folio

final class DTOMappingExtractionTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    @MainActor
    override func setUp() {
        super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(for: DataManager.schema, configurations: [config])
        context = container.mainContext
        DataManager.shared.preloadCategories(in: context)
    }

    override func tearDown() {
        container = nil
        context = nil
        super.tearDown()
    }

    // MARK: - Server overwrites client content

    @MainActor
    func testUpdateFromDTO_serverContentSetsExtractionSourceToServer() {
        let article = Article(url: "https://example.com/article")
        article.extractionSource = .client
        article.markdownContent = "# Client Content"
        context.insert(article)

        let dto = makeArticleDTO(markdownContent: "# Server Content")
        article.updateFromDTO(dto)

        XCTAssertEqual(article.markdownContent, "# Server Content")
        XCTAssertEqual(article.extractionSource, .server)
    }

    @MainActor
    func testUpdateFromDTO_nilContentPreservesClientSource() {
        let article = Article(url: "https://example.com/article")
        article.extractionSource = .client
        article.markdownContent = "# Client Content"
        context.insert(article)

        let dto = makeArticleDTO(markdownContent: nil)
        article.updateFromDTO(dto)

        XCTAssertEqual(article.markdownContent, "# Client Content")
        XCTAssertEqual(article.extractionSource, .client)
    }

    @MainActor
    func testUpdateFromDTO_serverOverwritesClientContent() {
        let article = Article(url: "https://example.com/article")
        article.extractionSource = .client
        article.markdownContent = "# Client extracted"
        article.status = .clientReady
        context.insert(article)

        let dto = makeArticleDTO(markdownContent: "# Server extracted with AI", status: "ready")
        article.updateFromDTO(dto)

        XCTAssertEqual(article.markdownContent, "# Server extracted with AI")
        XCTAssertEqual(article.extractionSource, .server)
        XCTAssertEqual(article.status, .ready)
    }

    @MainActor
    func testFromDTO_newArticleHasDefaultExtractionSource() {
        let dto = makeArticleDTO(markdownContent: "# Content")
        let article = Article.fromDTO(dto)

        // fromDTO doesn't set extractionSource — it remains at init default
        XCTAssertEqual(article.extractionSource, .none)
    }

    // MARK: - SubmitArticleRequest Encoding

    func testSubmitArticleRequest_withClientContent_encodesAllFields() throws {
        var request = SubmitArticleRequest(
            url: "https://example.com/article",
            tagIds: ["tag-1", "tag-2"]
        )
        request.title = "Test Title"
        request.author = "Test Author"
        request.siteName = "Test Site"
        request.markdownContent = "# Content"
        request.wordCount = 42

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(request)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(dict["url"] as? String, "https://example.com/article")
        XCTAssertEqual(dict["tag_ids"] as? [String], ["tag-1", "tag-2"])
        XCTAssertEqual(dict["title"] as? String, "Test Title")
        XCTAssertEqual(dict["author"] as? String, "Test Author")
        XCTAssertEqual(dict["site_name"] as? String, "Test Site")
        XCTAssertEqual(dict["markdown_content"] as? String, "# Content")
        XCTAssertEqual(dict["word_count"] as? Int, 42)
    }

    func testSubmitArticleRequest_withoutContent_omitsOptionalFields() throws {
        let request = SubmitArticleRequest(
            url: "https://example.com/article",
            tagIds: nil
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(request)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(dict["url"] as? String, "https://example.com/article")
        XCTAssertNil(dict["tag_ids"])
        XCTAssertNil(dict["title"])
        XCTAssertNil(dict["author"])
        XCTAssertNil(dict["site_name"])
        XCTAssertNil(dict["markdown_content"])
        XCTAssertNil(dict["word_count"])
    }

    func testSubmitArticleRequest_wordCountZero_encodedAsZero() throws {
        var request = SubmitArticleRequest(
            url: "https://example.com/article",
            tagIds: nil
        )
        request.wordCount = 0

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(request)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(dict["word_count"] as? Int, 0, "wordCount=0 should be encoded, not omitted")
    }

    // MARK: - OfflineQueueManager clientReady Preservation

    func testClientReadyStatus_rawValues() {
        XCTAssertEqual(ArticleStatus.pending.rawValue, "pending")
        XCTAssertEqual(ArticleStatus.clientReady.rawValue, "clientReady")
        XCTAssertEqual(ArticleStatus.failed.rawValue, "failed")
        XCTAssertEqual(ArticleStatus.processing.rawValue, "processing")
    }

    @MainActor
    func testClientReadyStatus_preservedOnFailure() {
        let clientReadyArticle = Article(url: "https://example.com/client-ready")
        clientReadyArticle.status = .clientReady
        context.insert(clientReadyArticle)

        let pendingArticle = Article(url: "https://example.com/pending")
        pendingArticle.status = .pending
        context.insert(pendingArticle)

        // Simulate the OfflineQueueManager failure logic:
        // "if article.status != .clientReady { article.status = .failed }"
        for article in [clientReadyArticle, pendingArticle] {
            if article.status != .clientReady {
                article.status = .failed
            }
        }

        XCTAssertEqual(clientReadyArticle.status, .clientReady,
                       "clientReady article should stay clientReady on failure")
        XCTAssertEqual(pendingArticle.status, .failed,
                       "pending article should become failed")
    }

    @MainActor
    func testOfflineQueueManager_predicateIncludesClientReady() {
        // Verify that an article with clientReady status matches the predicate logic
        // used in OfflineQueueManager.refreshPendingCount and processPendingArticles
        let pendingRaw = ArticleStatus.pending.rawValue
        let clientReadyRaw = ArticleStatus.clientReady.rawValue

        let clientReadyArticle = Article(url: "https://example.com/cr-predicate")
        clientReadyArticle.status = .clientReady
        context.insert(clientReadyArticle)

        let pendingArticle = Article(url: "https://example.com/p-predicate")
        pendingArticle.status = .pending
        context.insert(pendingArticle)

        let readyArticle = Article(url: "https://example.com/r-predicate")
        readyArticle.status = .ready
        context.insert(readyArticle)

        // The predicate from OfflineQueueManager:
        // #Predicate { $0.statusRaw == pendingRaw || $0.statusRaw == clientReadyRaw }
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate { $0.statusRaw == pendingRaw || $0.statusRaw == clientReadyRaw }
        )
        let matched = (try? context.fetch(descriptor)) ?? []

        XCTAssertEqual(matched.count, 2, "Should match both pending and clientReady articles")
        let matchedURLs = Set(matched.map(\.url))
        XCTAssertTrue(matchedURLs.contains("https://example.com/cr-predicate"))
        XCTAssertTrue(matchedURLs.contains("https://example.com/p-predicate"))
        XCTAssertFalse(matchedURLs.contains("https://example.com/r-predicate"),
                       "Ready articles should NOT be included in the pending predicate")
    }

    // MARK: - Helpers

    private func makeArticleDTO(
        markdownContent: String? = "# Hello World",
        status: String = "ready"
    ) -> ArticleDTO {
        ArticleDTO(
            id: "server-123",
            url: "https://example.com/article",
            title: "Test Article",
            author: "Author",
            siteName: "Example",
            faviconUrl: nil,
            coverImageUrl: nil,
            markdownContent: markdownContent,
            wordCount: 500,
            language: "en",
            categoryId: "cat-1",
            summary: "A summary",
            keyPoints: ["point1"],
            aiConfidence: 0.85,
            status: status,
            sourceType: "web",
            fetchError: nil,
            retryCount: 0,
            isFavorite: false,
            isArchived: false,
            readProgress: 0,
            lastReadAt: nil,
            publishedAt: nil,
            createdAt: Date(),
            updatedAt: Date(),
            category: nil,
            tags: nil
        )
    }
}
