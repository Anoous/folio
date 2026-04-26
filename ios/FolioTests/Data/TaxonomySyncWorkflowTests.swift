import XCTest
import SwiftData
@testable import Folio

private final class TaxonomySyncWorkflowMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (Data, HTTPURLResponse))?
    nonisolated(unsafe) static var requestPaths: [String] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requestPaths.append(request.url?.path ?? "")
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (data, response) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class TaxonomySyncWorkflowTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var apiClient: APIClient!
    private var keychainManager: KeyChainManager!
    private let baseURL = URL(string: "https://test.folio.app")!

    @MainActor
    override func setUp() {
        super.setUp()
        container = try! DataManager.createInMemoryContainer()
        context = container.mainContext

        keychainManager = KeyChainManager(service: "com.folio.taxonomy-sync-tests.\(UUID())")
        try? keychainManager.clearTokens()
        try? keychainManager.saveTokens(access: "test-token", refresh: "test-refresh")

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TaxonomySyncWorkflowMockURLProtocol.self]
        apiClient = APIClient(
            baseURL: baseURL,
            keychainManager: keychainManager,
            session: URLSession(configuration: config)
        )

        TaxonomySyncWorkflowMockURLProtocol.requestHandler = nil
        TaxonomySyncWorkflowMockURLProtocol.requestPaths = []
    }

    override func tearDown() {
        TaxonomySyncWorkflowMockURLProtocol.requestHandler = nil
        TaxonomySyncWorkflowMockURLProtocol.requestPaths = []
        try? keychainManager.clearTokens()
        keychainManager = nil
        apiClient = nil
        container = nil
        context = nil
        super.tearDown()
    }

    private func makeResponse(statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: baseURL, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
    }

    private func categoriesJSON(
        id: String = "cat-server-tech",
        slug: String = "tech",
        nameZH: String = "科技",
        nameEN: String = "Technology",
        icon: String = "cpu",
        sortOrder: Int = 0
    ) -> Data {
        """
        {
            "data": [{
                "id": "\(id)",
                "slug": "\(slug)",
                "name_zh": "\(nameZH)",
                "name_en": "\(nameEN)",
                "icon": "\(icon)",
                "sort_order": \(sortOrder),
                "created_at": "2025-01-01T00:00:00Z"
            }],
            "pagination": {"page": 1, "per_page": 20, "total": 1}
        }
        """.data(using: .utf8)!
    }

    private func tagsJSON(
        id: String = "tag-srv-1",
        name: String = "Swift",
        isAIGenerated: Bool = true,
        articleCount: Int = 3
    ) -> Data {
        """
        {
            "data": [{
                "id": "\(id)",
                "name": "\(name)",
                "is_ai_generated": \(isAIGenerated),
                "article_count": \(articleCount),
                "created_at": "2025-01-01T00:00:00Z"
            }],
            "pagination": {"page": 1, "per_page": 20, "total": 1}
        }
        """.data(using: .utf8)!
    }

    @MainActor
    func testSyncCategoriesUpdatesExistingBySlug() async throws {
        TaxonomySyncWorkflowMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/categories")
            return (
                self.categoriesJSON(id: "cat-server-tech", slug: "tech", nameZH: "技术", nameEN: "Tech"),
                self.makeResponse(statusCode: 200)
            )
        }

        let workflow = TaxonomySyncWorkflow(apiClient: apiClient, context: context)
        await workflow.syncCategories()

        let categoryRepo = CategoryRepository(context: context)
        let tech = try XCTUnwrap(categoryRepo.fetchBySlug("tech"))
        XCTAssertEqual(tech.serverID, "cat-server-tech")
        XCTAssertEqual(tech.nameZH, "技术")
        XCTAssertEqual(tech.nameEN, "Tech")
    }

    @MainActor
    func testSyncCategoriesUpdatesExistingByServerID() async throws {
        let local = Category(slug: "local", nameZH: "本地", nameEN: "Local", icon: "folder")
        local.serverID = "cat-server-local"
        context.insert(local)
        try context.save()

        TaxonomySyncWorkflowMockURLProtocol.requestHandler = { _ in
            (
                self.categoriesJSON(
                    id: "cat-server-local",
                    slug: "remote",
                    nameZH: "远端",
                    nameEN: "Remote",
                    icon: "cloud",
                    sortOrder: 12
                ),
                self.makeResponse(statusCode: 200)
            )
        }

        let workflow = TaxonomySyncWorkflow(apiClient: apiClient, context: context)
        await workflow.syncCategories()

        XCTAssertEqual(local.nameZH, "远端")
        XCTAssertEqual(local.nameEN, "Remote")
        XCTAssertEqual(local.icon, "cloud")
        XCTAssertEqual(local.sortOrder, 12)
    }

    @MainActor
    func testSyncTagsCreatesNewTag() async throws {
        TaxonomySyncWorkflowMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/tags")
            return (
                self.tagsJSON(id: "tag-srv-new", name: "NewTag", articleCount: 5),
                self.makeResponse(statusCode: 200)
            )
        }

        let workflow = TaxonomySyncWorkflow(apiClient: apiClient, context: context)
        await workflow.syncTags()

        let tagRepo = TagRepository(context: context)
        let tag = try XCTUnwrap(tagRepo.fetchByName("NewTag"))
        XCTAssertEqual(tag.serverID, "tag-srv-new")
        XCTAssertEqual(tag.articleCount, 5)
    }

    @MainActor
    func testSyncTagsUpdatesExistingByName() async throws {
        let local = Tag(name: "Swift", isAIGenerated: false)
        context.insert(local)
        try context.save()

        TaxonomySyncWorkflowMockURLProtocol.requestHandler = { _ in
            (
                self.tagsJSON(id: "tag-srv-swift", name: "Swift", isAIGenerated: true, articleCount: 10),
                self.makeResponse(statusCode: 200)
            )
        }

        let workflow = TaxonomySyncWorkflow(apiClient: apiClient, context: context)
        await workflow.syncTags()

        XCTAssertEqual(local.serverID, "tag-srv-swift")
        XCTAssertTrue(local.isAIGenerated)
        XCTAssertEqual(local.articleCount, 10)
    }
}
