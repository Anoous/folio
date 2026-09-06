import XCTest
import SwiftData
@testable import Folio

// MARK: - Mock URL Protocol for SyncService Tests

private final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (Data, HTTPURLResponse))?
    nonisolated(unsafe) static var lastRequestBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private func requestBodyData() -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return nil
        }
        stream.open()
        let bufferSize = 4096
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer {
            buffer.deallocate()
            stream.close()
        }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read > 0 {
                data.append(buffer, count: read)
            } else {
                break
            }
        }
        return data
    }

    override func startLoading() {
        MockURLProtocol.lastRequestBody = requestBodyData()
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

private final class RequestPathRecorder: @unchecked Sendable {
    var values: [String] = []
}

private final class RequestBodyRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var value: [String: Any]?

    func set(_ body: [String: Any]?) {
        lock.lock()
        value = body
        lock.unlock()
    }

    func currentValue() -> [String: Any]? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }

    func currentValue() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
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
        MockURLProtocol.lastRequestBody = nil
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        MockURLProtocol.lastRequestBody = nil
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
    func testSubmitPending_preservesLocalFavoriteAsPendingFieldUpdate() async throws {
        let article = Article(url: "https://example.com/submit-favorite")
        article.syncState = .pendingUpload
        article.isFavorite = true
        context.insert(article)
        try context.save()

        let submitJSON = """
        {"article_id": "server-art-2", "task_id": "task-2"}
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            let path = request.url?.path ?? ""
            if path.contains("articles") {
                return (submitJSON, self.makeResponse(statusCode: 202))
            }
            let taskJSON = """
            {"id":"task-2","url":"https://example.com","status":"done","article_id":"server-art-2","retry_count":0,"created_at":"2025-01-01T00:00:00Z","updated_at":"2025-01-01T00:00:00Z"}
            """.data(using: .utf8)!
            return (taskJSON, self.makeResponse(statusCode: 200))
        }

        let syncService = SyncService(apiClient: apiClient, context: context)
        let results = await syncService.submitPendingArticles([article])

        XCTAssertEqual(results[article.id], true)
        XCTAssertEqual(article.serverID, "server-art-2")
        XCTAssertEqual(article.syncState, .pendingUpdate)
        XCTAssertTrue(article.dirtyFields.contains(.favorite))
        XCTAssertNotNil(article.favoriteUpdatedAt)
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

    // MARK: - performFullSync

    @MainActor
    func testPerformFullSync_pushesPendingUpdatesBeforeListingArticles() async throws {
        let article = Article(url: "https://example.com/pending-update")
        article.serverID = "server-1"
        article.syncState = .pendingUpdate
        article.isFavorite = true
        article.dirtyFields = [.favorite]
        context.insert(article)
        try context.save()

        let recorder = RequestPathRecorder()
        MockURLProtocol.requestHandler = { request in
            let path = request.url?.path ?? ""
            recorder.values.append("\(request.httpMethod ?? "GET") \(path)")

            switch (request.httpMethod ?? "GET", path) {
            case ("PUT", "/api/v1/articles/server-1"):
                return (Data(), self.makeResponse(statusCode: 200))
            case ("GET", "/api/v1/categories"):
                let json = """
                {"data":[],"pagination":{"page":1,"per_page":20,"total":0}}
                """.data(using: .utf8)!
                return (json, self.makeResponse(statusCode: 200))
            case ("GET", "/api/v1/tags"):
                let json = """
                {"data":[],"pagination":{"page":1,"per_page":20,"total":0}}
                """.data(using: .utf8)!
                return (json, self.makeResponse(statusCode: 200))
            case ("GET", "/api/v1/articles"):
                let json = """
                {
                  "data": [],
                  "pagination": {"page": 1, "per_page": 50, "total": 0},
                  "server_time": "2025-01-01T00:00:00Z",
                  "sync_epoch": 1
                }
                """.data(using: .utf8)!
                return (json, self.makeResponse(statusCode: 200))
            case ("POST", "/api/v1/auth/refresh"):
                let json = """
                {
                  "access_token":"new-token",
                  "refresh_token":"new-refresh",
                  "expires_in":3600,
                  "user":{
                    "id":"user-1",
                    "email":"test@example.com",
                    "nickname":"tester",
                    "avatar_url":null,
                    "subscription":"free",
                    "subscription_expires_at":null,
                    "monthly_quota":100,
                    "current_month_count":1,
                    "preferred_language":"en",
                    "created_at":"2025-01-01T00:00:00Z",
                    "updated_at":"2025-01-01T00:00:00Z",
                    "sync_epoch":1
                  }
                }
                """.data(using: .utf8)!
                return (json, self.makeResponse(statusCode: 200))
            default:
                XCTFail("Unexpected request: \(request.httpMethod ?? "GET") \(path)")
                return (Data(), self.makeResponse(statusCode: 500))
            }
        }

        let syncService = SyncService(apiClient: apiClient, context: context)
        await syncService.performFullSync()

        let updateIndex = recorder.values.firstIndex(of: "PUT /api/v1/articles/server-1")
        let listIndex = recorder.values.firstIndex(of: "GET /api/v1/articles")

        XCTAssertNotNil(updateIndex)
        XCTAssertNotNil(listIndex)
        XCTAssertLessThan(updateIndex!, listIndex!)
    }

    @MainActor
    func testPerformFullSync_readProgressPendingUpdateSendsSparsePatch() async throws {
        let article = Article(url: "https://example.com/progress-only")
        article.serverID = "server-1"
        article.syncState = .pendingUpdate
        article.status = .ready
        article.isFavorite = false
        article.isArchived = false
        article.readProgress = 0.6
        article.dirtyFields = [.readProgress]
        context.insert(article)
        try context.save()

        let requestBody = RequestBodyRecorder()
        MockURLProtocol.requestHandler = { request in
            let path = request.url?.path ?? ""

            switch (request.httpMethod ?? "GET", path) {
            case ("PUT", "/api/v1/articles/server-1"):
                let body = MockURLProtocol.lastRequestBody.flatMap {
                    try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
                }
                requestBody.set(body)
                return (Data(), self.makeResponse(statusCode: 200))
            case ("GET", "/api/v1/categories"):
                let json = """
                {"data":[],"pagination":{"page":1,"per_page":20,"total":0}}
                """.data(using: .utf8)!
                return (json, self.makeResponse(statusCode: 200))
            case ("GET", "/api/v1/tags"):
                let json = """
                {"data":[],"pagination":{"page":1,"per_page":20,"total":0}}
                """.data(using: .utf8)!
                return (json, self.makeResponse(statusCode: 200))
            case ("GET", "/api/v1/articles"):
                let json = """
                {
                  "data": [{
                    "id":"server-1",
                    "url":"https://example.com/progress-only",
                    "title":"Progress Only",
                    "author":null,
                    "site_name":"Example",
                    "favicon_url":null,
                    "cover_image_url":null,
                    "markdown_content":null,
                    "language":null,
                    "category_id":null,
                    "summary":null,
                    "key_points":[],
                    "ai_confidence":null,
                    "source_type":"web",
                    "fetch_error":null,
                    "retry_count":0,
                    "word_count":100,
                    "is_favorite":false,
                    "is_archived":false,
                    "read_progress":0.6,
                    "last_read_at":null,
                    "published_at":null,
                    "status":"ready",
                    "created_at":"2025-01-01T00:00:00Z",
                    "updated_at":"2025-01-01T00:00:00Z",
                    "deleted_at":null,
                    "category":null,
                    "tags":[]
                  }],
                  "pagination": {"page": 1, "per_page": 50, "total": 1},
                  "server_time": "2025-01-01T00:00:00Z",
                  "sync_epoch": 1
                }
                """.data(using: .utf8)!
                return (json, self.makeResponse(statusCode: 200))
            case ("POST", "/api/v1/auth/refresh"):
                let json = """
                {
                  "access_token":"new-token",
                  "refresh_token":"new-refresh",
                  "expires_in":3600,
                  "user":{
                    "id":"user-1",
                    "email":"test@example.com",
                    "nickname":"tester",
                    "avatar_url":null,
                    "subscription":"free",
                    "subscription_expires_at":null,
                    "monthly_quota":100,
                    "current_month_count":1,
                    "preferred_language":"en",
                    "created_at":"2025-01-01T00:00:00Z",
                    "updated_at":"2025-01-01T00:00:00Z",
                    "sync_epoch":1
                  }
                }
                """.data(using: .utf8)!
                return (json, self.makeResponse(statusCode: 200))
            default:
                XCTFail("Unexpected request: \(request.httpMethod ?? "GET") \(path)")
                return (Data(), self.makeResponse(statusCode: 500))
            }
        }

        let syncService = SyncService(apiClient: apiClient, context: context)
        await syncService.performFullSync()

        let body = requestBody.currentValue()
        XCTAssertNil(body?["is_favorite"])
        XCTAssertNil(body?["is_archived"])
        XCTAssertEqual(body?["read_progress"] as? Double, 0.6)
        XCTAssertNotNil(body?["read_progress_updated_at"] as? String)
        XCTAssertNil(body?["favorite_updated_at"])
        XCTAssertNil(body?["archived_updated_at"])
        XCTAssertEqual(article.syncState, .synced)
        XCTAssertTrue(article.dirtyFields.isEmpty)
    }

    @MainActor
    func testPerformFullSync_cancelsExistingPollersBeforeTheyHitTaskEndpoint() async throws {
        let article = Article(url: "https://example.com/poll-cancel")
        article.syncState = .pendingUpload
        context.insert(article)
        try context.save()

        let pollRequests = LockedCounter()
        let submitJSON = """
        {"article_id": "server-art-1", "task_id": "task-1"}
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            let path = request.url?.path ?? ""

            switch (request.httpMethod ?? "GET", path) {
            case ("POST", "/api/v1/articles"):
                return (submitJSON, self.makeResponse(statusCode: 202))
            case ("GET", "/api/v1/tasks/task-1"):
                pollRequests.increment()
                let taskJSON = """
                {"id":"task-1","url":"https://example.com","status":"queued","article_id":null,"retry_count":0,"created_at":"2025-01-01T00:00:00Z","updated_at":"2025-01-01T00:00:00Z"}
                """.data(using: .utf8)!
                return (taskJSON, self.makeResponse(statusCode: 200))
            case ("GET", "/api/v1/categories"):
                let json = """
                {"data":[],"pagination":{"page":1,"per_page":20,"total":0}}
                """.data(using: .utf8)!
                return (json, self.makeResponse(statusCode: 200))
            case ("GET", "/api/v1/tags"):
                let json = """
                {"data":[],"pagination":{"page":1,"per_page":20,"total":0}}
                """.data(using: .utf8)!
                return (json, self.makeResponse(statusCode: 200))
            case ("GET", "/api/v1/articles"):
                let json = """
                {
                  "data": [],
                  "pagination": {"page": 1, "per_page": 50, "total": 0},
                  "server_time": "2025-01-01T00:00:00Z",
                  "sync_epoch": 1
                }
                """.data(using: .utf8)!
                return (json, self.makeResponse(statusCode: 200))
            case ("POST", "/api/v1/auth/refresh"):
                let json = """
                {
                  "access_token":"new-token",
                  "refresh_token":"new-refresh",
                  "expires_in":3600,
                  "user":{
                    "id":"user-1",
                    "email":"test@example.com",
                    "nickname":"tester",
                    "avatar_url":null,
                    "subscription":"free",
                    "subscription_expires_at":null,
                    "monthly_quota":100,
                    "current_month_count":1,
                    "preferred_language":"en",
                    "created_at":"2025-01-01T00:00:00Z",
                    "updated_at":"2025-01-01T00:00:00Z",
                    "sync_epoch":1
                  }
                }
                """.data(using: .utf8)!
                return (json, self.makeResponse(statusCode: 200))
            default:
                XCTFail("Unexpected request: \(request.httpMethod ?? "GET") \(path)")
                return (Data(), self.makeResponse(statusCode: 500))
            }
        }

        let syncService = SyncService(apiClient: apiClient, context: context)
        let results = await syncService.submitPendingArticles([article])
        XCTAssertEqual(results[article.id], true)

        await Task.yield()
        await syncService.performFullSync()
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(pollRequests.currentValue(), 0)
    }
}
