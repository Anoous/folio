import XCTest
import SwiftData
@testable import Folio

// MARK: - Mock URL Protocol for SyncService Tests

private final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (Data, HTTPURLResponse))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
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

// MARK: - SyncService Tests

final class SyncServiceTests: XCTestCase {

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

        keychainManager = KeyChainManager(service: "com.folio.sync-tests")
        try? keychainManager.clearTokens()
        try? keychainManager.saveTokens(access: "test-token", refresh: "test-refresh")

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        apiClient = APIClient(baseURL: baseURL, keychainManager: keychainManager, session: session)
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
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

    // MARK: - submitPendingArticles

    @MainActor
    func testSubmitPending_success_setsServerID() async throws {
        let article = Article(url: "https://example.com/submit-test")
        article.syncState = .pendingUpload
        context.insert(article)
        try context.save()

        let submitJSON = """
        {"article_id": "server-art-1", "task_id": "task-1"}
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            let path = request.url?.path ?? ""
            if path.contains("articles") {
                return (submitJSON, self.makeResponse(statusCode: 202))
            }
            // For task polling — return done immediately
            let taskJSON = """
            {"id":"task-1","url":"https://example.com","status":"done","article_id":"server-art-1","retry_count":0,"created_at":"2025-01-01T00:00:00Z","updated_at":"2025-01-01T00:00:00Z"}
            """.data(using: .utf8)!
            return (taskJSON, self.makeResponse(statusCode: 200))
        }

        let syncService = SyncService(apiClient: apiClient, context: context)
        let results = await syncService.submitPendingArticles([article])

        XCTAssertEqual(results[article.id], true)
        XCTAssertEqual(article.serverID, "server-art-1")
        XCTAssertEqual(article.syncState, .synced)
    }

    @MainActor
    func testSubmitPending_failure_staysPending() async throws {
        let article = Article(url: "https://example.com/fail-test")
        article.syncState = .pendingUpload
        context.insert(article)
        try context.save()

        MockURLProtocol.requestHandler = { _ in
            (Data(), self.makeResponse(statusCode: 500))
        }

        let syncService = SyncService(apiClient: apiClient, context: context)
        let results = await syncService.submitPendingArticles([article])

        XCTAssertEqual(results[article.id], false)
        XCTAssertEqual(article.syncState, .pendingUpload)
    }

    @MainActor
    func testSubmitPending_quotaExceeded_marksFailed() async throws {
        let article = Article(url: "https://example.com/quota-test")
        article.syncState = .pendingUpload
        context.insert(article)
        try context.save()

        MockURLProtocol.requestHandler = { _ in
            (Data(), self.makeResponse(statusCode: 429))
        }

        let syncService = SyncService(apiClient: apiClient, context: context)
        let results = await syncService.submitPendingArticles([article])

        XCTAssertEqual(results[article.id], false)
        XCTAssertEqual(article.status, .failed)
        XCTAssertNotNil(article.fetchError)
    }

    // MARK: - syncCategories

    @MainActor
    func testSyncCategories_updatesExisting() async throws {
        let json = """
        {
            "data": [{
                "id": "cat-server-tech",
                "slug": "tech",
                "name_zh": "科技",
                "name_en": "Technology",
                "icon": "cpu",
                "sort_order": 0,
                "created_at": "2025-01-01T00:00:00Z"
            }],
            "pagination": {"page": 1, "per_page": 20, "total": 1}
        }
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { _ in
            (json, self.makeResponse(statusCode: 200))
        }

        let syncService = SyncService(apiClient: apiClient, context: context)
        await syncService.syncCategories()

        let categoryRepo = CategoryRepository(context: context)
        let tech = try categoryRepo.fetchBySlug("tech")
        XCTAssertNotNil(tech)
        XCTAssertEqual(tech?.serverID, "cat-server-tech")
    }

    // MARK: - syncTags

    @MainActor
    func testSyncTags_createsNew() async throws {
        let json = """
        {
            "data": [{
                "id": "tag-srv-1",
                "name": "NewTag",
                "is_ai_generated": true,
                "article_count": 3,
                "created_at": "2025-01-01T00:00:00Z"
            }],
            "pagination": {"page": 1, "per_page": 20, "total": 1}
        }
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { _ in
            (json, self.makeResponse(statusCode: 200))
        }

        let syncService = SyncService(apiClient: apiClient, context: context)
        await syncService.syncTags()

        let tagRepo = TagRepository(context: context)
        let tag = try tagRepo.fetchByName("NewTag")
        XCTAssertNotNil(tag)
        XCTAssertEqual(tag?.serverID, "tag-srv-1")
    }

    @MainActor
    func testSyncTags_updatesExistingByName() async throws {
        // Create local tag without serverID
        let localTag = Tag(name: "Swift", isAIGenerated: false)
        context.insert(localTag)
        try context.save()

        let json = """
        {
            "data": [{
                "id": "tag-srv-swift",
                "name": "Swift",
                "is_ai_generated": true,
                "article_count": 10,
                "created_at": "2025-01-01T00:00:00Z"
            }],
            "pagination": {"page": 1, "per_page": 20, "total": 1}
        }
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { _ in
            (json, self.makeResponse(statusCode: 200))
        }

        let syncService = SyncService(apiClient: apiClient, context: context)
        await syncService.syncTags()

        XCTAssertEqual(localTag.serverID, "tag-srv-swift")
        XCTAssertTrue(localTag.isAIGenerated)
        XCTAssertEqual(localTag.articleCount, 10)
    }
}
