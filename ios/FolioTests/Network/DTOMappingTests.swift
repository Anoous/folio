import XCTest
import SwiftData
@testable import Folio

final class DTOMappingTests: XCTestCase {
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

    // MARK: - Article.fromDTO

    @MainActor
    func testArticleFromDTO() {
        let dto = makeArticleDTO()
        let article = Article.fromDTO(dto)

        XCTAssertEqual(article.serverID, "server-123")
        XCTAssertEqual(article.url, "https://example.com/article")
        XCTAssertEqual(article.title, "Test Article")
        XCTAssertEqual(article.author, "Author")
        XCTAssertEqual(article.siteName, "Example")
        XCTAssertEqual(article.summary, "A summary")
        XCTAssertEqual(article.keyPoints, ["point1", "point2"])
        XCTAssertEqual(article.aiConfidence, 0.85)
        XCTAssertEqual(article.status, .ready)
        XCTAssertEqual(article.sourceType, .web)
        XCTAssertEqual(article.syncState, .synced)
        XCTAssertEqual(article.wordCount, 500)
        XCTAssertEqual(article.language, "en")
        XCTAssertTrue(article.isFavorite)
        XCTAssertFalse(article.isArchived)
    }

    @MainActor
    func testArticleFromDTONilKeyPointsDefaultsToEmpty() {
        var dto = makeArticleDTO()
        dto = ArticleDTO(
            id: dto.id, url: dto.url, title: dto.title, author: dto.author,
            siteName: dto.siteName, faviconUrl: dto.faviconUrl, coverImageUrl: dto.coverImageUrl,
            markdownContent: dto.markdownContent, wordCount: dto.wordCount, language: dto.language,
            categoryId: dto.categoryId, summary: dto.summary,
            keyPoints: nil, aiConfidence: nil,
            status: dto.status, sourceType: dto.sourceType, fetchError: dto.fetchError,
            retryCount: dto.retryCount, isFavorite: dto.isFavorite, isArchived: dto.isArchived,
            readProgress: dto.readProgress, lastReadAt: dto.lastReadAt, publishedAt: dto.publishedAt,
            createdAt: dto.createdAt, updatedAt: dto.updatedAt,
            category: dto.category, tags: dto.tags
        )

        let article = Article.fromDTO(dto)
        XCTAssertEqual(article.keyPoints, [])
        XCTAssertEqual(article.aiConfidence, 0)
    }

    // MARK: - Article.updateFromDTO

    @MainActor
    func testUpdateFromDTOSetsSyncStateToSynced() {
        let article = Article(url: "https://example.com/article")
        article.syncState = .pendingUpload
        context.insert(article)

        let dto = makeArticleDTO()
        article.updateFromDTO(dto)

        XCTAssertEqual(article.syncState, .synced)
        XCTAssertEqual(article.serverID, "server-123")
        XCTAssertEqual(article.title, "Test Article")
    }

    // MARK: - Tag.fromDTO

    @MainActor
    func testTagFromDTO() {
        let dto = TagDTO(
            id: "tag-1",
            name: "Swift",
            isAiGenerated: true,
            articleCount: 5,
            createdAt: Date()
        )

        let tag = Tag.fromDTO(dto)
        XCTAssertEqual(tag.serverID, "tag-1")
        XCTAssertEqual(tag.name, "Swift")
        XCTAssertTrue(tag.isAIGenerated)
        XCTAssertEqual(tag.articleCount, 5)
    }

    // MARK: - Tag.updateFromDTO

    @MainActor
    func testTagUpdateFromDTO() {
        let tag = Tag(name: "swift", isAIGenerated: false)
        context.insert(tag)

        let dto = TagDTO(
            id: "tag-server-1",
            name: "Swift",
            isAiGenerated: true,
            articleCount: 10,
            createdAt: Date()
        )

        tag.updateFromDTO(dto)
        XCTAssertEqual(tag.serverID, "tag-server-1")
        XCTAssertEqual(tag.name, "Swift")
        XCTAssertTrue(tag.isAIGenerated)
        XCTAssertEqual(tag.articleCount, 10)
    }

    // MARK: - Category.updateFromDTO

    @MainActor
    func testCategoryUpdateFromDTO() {
        let categoryRepo = CategoryRepository(context: context)
        guard let techCategory = try? categoryRepo.fetchBySlug("tech") else {
            XCTFail("Preloaded tech category not found")
            return
        }

        XCTAssertNil(techCategory.serverID)

        let dto = CategoryDTO(
            id: "cat-server-1",
            slug: "tech",
            nameZh: "科技",
            nameEn: "Tech",
            icon: "cpu",
            sortOrder: 0,
            createdAt: Date()
        )

        techCategory.updateFromDTO(dto)
        XCTAssertEqual(techCategory.serverID, "cat-server-1")
    }

    // MARK: - Repository fetchByServerID

    @MainActor
    func testArticleRepositoryFetchByServerID() throws {
        let article = Article(url: "https://example.com")
        article.serverID = "server-abc"
        context.insert(article)
        try context.save()

        let repo = ArticleRepository(context: context)
        let found = try repo.fetchByServerID("server-abc")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.id, article.id)

        let notFound = try repo.fetchByServerID("nonexistent")
        XCTAssertNil(notFound)
    }

    @MainActor
    func testTagRepositoryFetchByServerID() throws {
        let tag = Tag(name: "Test")
        tag.serverID = "tag-server-1"
        context.insert(tag)
        try context.save()

        let repo = TagRepository(context: context)
        let found = try repo.fetchByServerID("tag-server-1")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.name, "Test")
    }

    @MainActor
    func testCategoryRepositoryFetchByServerID() throws {
        let categoryRepo = CategoryRepository(context: context)
        guard let tech = try categoryRepo.fetchBySlug("tech") else {
            XCTFail("Tech category not found")
            return
        }
        tech.serverID = "cat-server-tech"
        try context.save()

        let found = try categoryRepo.fetchByServerID("cat-server-tech")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.slug, "tech")
    }

    // MARK: - Helpers

    private func makeArticleDTO() -> ArticleDTO {
        ArticleDTO(
            id: "server-123",
            url: "https://example.com/article",
            title: "Test Article",
            author: "Author",
            siteName: "Example",
            faviconUrl: "https://example.com/favicon.ico",
            coverImageUrl: nil,
            markdownContent: "# Hello World",
            wordCount: 500,
            language: "en",
            categoryId: "cat-1",
            summary: "A summary",
            keyPoints: ["point1", "point2"],
            aiConfidence: 0.85,
            status: "ready",
            sourceType: "web",
            fetchError: nil,
            retryCount: 0,
            isFavorite: true,
            isArchived: false,
            readProgress: 0.5,
            lastReadAt: nil,
            publishedAt: nil,
            createdAt: Date(),
            updatedAt: Date(),
            category: CategoryDTO(
                id: "cat-1",
                slug: "tech",
                nameZh: "技术",
                nameEn: "Technology",
                icon: "cpu",
                sortOrder: 0,
                createdAt: Date()
            ),
            tags: [
                TagDTO(id: "tag-1", name: "Swift", isAiGenerated: true, articleCount: 3, createdAt: Date())
            ]
        )
    }
}
